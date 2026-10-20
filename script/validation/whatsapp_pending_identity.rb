unless Rails.env.test? && ActiveRecord::Base.connection_db_config.database == 'viperchat_provider_identity_test'
  raise 'Wrong database: refusing validation'
end

require 'webmock'
WebMock.enable!
WebMock.disable_net_connect!
ActiveJob::Base.queue_adapter = :test
require 'factory_bot_rails'
require 'rspec/mocks/standalone'
FactoryBot.find_definitions unless FactoryBot.factories.registered?(:account)

checks = []
assert = lambda { |condition, label|
  raise "FAILED: #{label}" unless condition

  checks << label
}
raw = Base64.strict_decode64('HBgTQlIuMTc2NTk0NjA5MTM1Mjk5NhUUABEYFjNFQjA0NDk2RUZFNTM3NTY0MTJCQjkA')
observer = Whatsapp::MessageIdentityObservationService
cloud = Whatsapp::IncomingMessageWhatsappCloudService
job = Whatsapp::ResolvePendingIdentityJob
resolver = Whatsapp::MessageIdentityContactResolver

# Each scenario is an independent durable-ingestion integration fixture.
# rubocop:disable Metrics/BlockLength
%w[outgoing incoming enriched conflict disabled exhausted shared_alias note schedule crash status_first].each_with_index do |scenario, index|
  business = "55669962224#{format('%02d', index)}"
  legacy_business = business[0..3] + business[5..]
  uno = FactoryBot.create(:channel_whatsapp, provider: 'unoapi', phone_number: "+#{business}",
                                             sync_templates: false, validate_provider_config: false)
  meta = FactoryBot.create(:channel_whatsapp, account: uno.account, provider: 'whatsapp_cloud', phone_number: "+#{legacy_business}",
                                              sync_templates: false, validate_provider_config: false)
  meta.update!(provider_config: meta.provider_config.merge(resolver::CONFIG_KEY => uno.inbox.id))
  old = FactoryBot.create(:contact, account: uno.account, name: 'Old human contact', phone_number: '+5566996651924',
                                    bsuid: '22364028932201@lid', custom_attributes: { 'manual' => 'preserve' })
  old_attributes = old.reload.attributes
  original = '3EB04496EFE53756412BB9'.sub(/..\z/, format('%02X', index))
  bytes = raw.sub('3EB04496EFE53756412BB9', original)
  incoming = scenario == 'incoming'
  bytes = bytes.sub("\x00\x11\x18", "\x00\x12\x18") if incoming
  wamid = "wamid.#{Base64.strict_encode64(bytes)}"
  event = { id: wamid, type: 'text', text: { body: 'Do not resend' } }
  event[incoming ? :from_user_id : :to_user_id] = 'BR.1765946091352996'
  event[incoming ? :to : :from] = legacy_business
  kind = incoming ? :messages : :message_echoes
  params = { entry: [{ changes: [{ value: { kind => [event] } }] }] }.with_indifferent_access

  cloud.new(inbox: meta.inbox.reload, params: params, outgoing_echo: !incoming).perform
  identity = WhatsappMessageIdentity.find_by!(inbox: meta.inbox, external_id: wamid)
  pending = WhatsappIdentityResolution.find_by!(whatsapp_message_identity: identity)
  link = meta.inbox.contact_inboxes.find_by!(source_id: 'BR.1765946091352996')
  provisional = link.contact
  message = meta.inbox.messages.find_by!(source_id: wamid)
  conversation = message.conversation
  assert.call(pending.state == 'pending' && pending.provisional_contact_id == provisional.id && provisional.id != old.id,
              "#{scenario}: Meta first creates one tracked pending placeholder")
  ids = [message.id, message.source_id, message.conversation_id, link.id, link.source_id]
  before_counts = [Contact.count, Conversation.count, Message.count]
  cloud.new(inbox: meta.inbox.reload, params: params, outgoing_echo: !incoming).perform
  assert.call(before_counts == [Contact.count, Conversation.count, Message.count], "#{scenario}: webhook repetition is idempotent")
  if scenario == 'shared_alias'
    other_event = event.merge(id: "wamid.#{Base64.strict_encode64(bytes.sub(original, '3EB04496EFE53756412BEE'))}")
    other_params = { entry: [{ changes: [{ value: { kind => [other_event] } }] }] }.with_indifferent_access
    cloud.new(inbox: meta.inbox.reload, params: other_params, outgoing_echo: true).perform
    assert.call(Contact.count == before_counts.first && meta.inbox.contact_inboxes.count == 1,
                'two pending messages share one owned placeholder and alias')
  end
  job.perform_now(pending.id)
  assert.call(pending.reload.attempts == 1 && pending.next_attempt_at > Time.current, "#{scenario}: durable bounded retry without evidence")
  job.perform_now(pending.id)
  assert.call(pending.reload.attempts == 1, "#{scenario}: early duplicate job does not repeat attempt")

  if scenario == 'enriched'
    provisional.update!(name: 'Manually corrected name')
  elsif scenario == 'note'
    FactoryBot.create(:note, account: uno.account, contact: provisional)
  elsif scenario == 'schedule'
    user = FactoryBot.create(:user, account: uno.account)
    ScheduledMessage.create!(account: uno.account, inbox: meta.inbox, contact: provisional, conversation: conversation,
                             label: FactoryBot.create(:label, account: uno.account), sender: user, created_by: user,
                             scheduled_at: 1.hour.from_now, content: 'Keep schedule')
  elsif scenario == 'conflict'
    link.additional_attributes.delete('identity_provisional_resolution_id')
    link.save!
  elsif scenario == 'disabled'
    meta.update!(provider_config: meta.provider_config.except(resolver::CONFIG_KEY))
  elsif scenario == 'exhausted'
    pending.update!(next_attempt_at: Time.current)
    job.perform_now
    recovered = ActiveJob::Base.queue_adapter.enqueued_jobs.any? { |item| item[:job] == job && item[:args] == [pending.id] }
    assert.call(recovered, 'periodic sweep recovers persisted due work without original enqueue')
    pending.update!(attempts: 11, next_attempt_at: Time.current)
    job.perform_now(pending.id)
    assert.call(pending.reload.state == 'review' && pending.attempts == 12, 'retry budget ends in visible review, not silent loss')
  end

  uno_conversation = FactoryBot.create(:conversation, account: uno.account, inbox: uno.inbox, contact: old)
  if scenario == 'status_first'
    observer.new(inbox: uno.inbox, value: { statuses: [{ id: "uno-public-#{index}", provider_message_id: original,
                                                         recipient_id: '5566996651924', status: 'sent' }] }).perform
    job.perform_now(pending.id)
    assert.call(pending.reload.state == 'pending' && pending.reason == 'contact_identity_pending',
                'status before counterpart message stays pending, without guessing contact')
  end
  uno_message = FactoryBot.create(:message, account: uno.account, inbox: uno.inbox, conversation: uno_conversation,
                                            source_id: "uno-public-#{index}", message_type: incoming ? :incoming : :outgoing)
  observation = { id: uno_message.source_id, provider_message_id: original, type: 'text' }
  observation[incoming ? :from : :to] = '5566996651924'
  observer.new(inbox: uno.inbox, value: { kind => [observation] }).perform unless scenario == 'status_first'
  assert.call(pending.reload.state == 'pending' && pending.next_attempt_at <= Time.current, "#{scenario}: counterpart wakes durable work")
  media = ActiveStorage::Blob.create_before_direct_upload!(filename: 'retained.pdf', byte_size: 1,
                                                           checksum: Base64.strict_encode64(Digest::MD5.digest('x')), content_type: 'application/pdf',
                                                           metadata: { identified: true, analyzed: true })
  attachment = message.attachments.create!(account: uno.account, file_type: :file, file: media)
  private_note = FactoryBot.create(:message, conversation: conversation, account: uno.account, inbox: meta.inbox, private: true)
  conversation.update_columns(status: Conversation.statuses[:resolved]) # rubocop:disable Rails/SkipsModelValidations
  state_before = conversation.reload.attributes.except('contact_id')
  total_messages = Message.count
  existing_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.size
  if scenario == 'crash'
    RSpec::Mocks.with_temporary_scope do
      allow_any_instance_of(Contact).to receive(:delete).and_raise(RuntimeError, 'simulated interrupted repair')
      begin
        job.perform_now(pending.id)
      rescue RuntimeError => e
        raise unless e.message == 'simulated interrupted repair'
      end
    end
    assert.call(pending.reload.reason == 'processing_error' && link.reload.contact_id == provisional.id && Contact.exists?(provisional.id),
                'crash rolls back alias, conversation and sender changes; persisted retry survives')
    pending.update!(next_attempt_at: Time.current)
    existing_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.size
  end
  if scenario == 'outgoing'
    threads = Array.new(2) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { job.perform_now(pending.id) }
      end
    end
    threads.each(&:value)
    assert.call(pending.reload.attempts == 2, 'two concurrent jobs resolve only once under the inbox lock')
  else
    job.perform_now(pending.id)
  end

  if %w[enriched conflict disabled note schedule].include?(scenario)
    expected = scenario == 'disabled' ? 'disabled' : 'conflict'
    assert.call(pending.reload.state == expected && link.reload.contact_id == provisional.id && provisional.reload.persisted?,
                "#{scenario}: no silent reassignment or deletion")
  else
    assert.call(pending.reload.state == 'resolved' && pending.resolved_contact_id == old.id,
                "#{scenario}: late exact original resolves to old contact")
    assert.call(!Contact.exists?(provisional.id) && link.reload.contact_id == old.id, "#{scenario}: only owned pristine placeholder consolidated")
    assert.call(message.reload.sender_id == old.id, 'incoming sender repaired without replay') if incoming
    assert.call(conversation.reload.contact_id == old.id && conversation.attributes.except('contact_id') == state_before,
                "#{scenario}: original resolved conversation IDs status and attributes retained")
  end
  assert.call(ids == [message.reload.id, message.source_id, message.conversation_id, link.reload.id, link.source_id],
              "#{scenario}: all existing public and internal message/alias/conversation IDs preserved")
  assert.call(uno_message.reload.conversation_id != message.conversation_id, "#{scenario}: inboxes and conversations remain separate")
  assert.call(old.reload.attributes == old_attributes, "#{scenario}: old contact fields and LID untouched")
  media_preserved = Attachment.exists?(attachment.id) && ActiveStorage::Blob.exists?(media.id)
  assert.call(Message.count == total_messages && media_preserved && private_note.reload.private?,
              "#{scenario}: no duplicate message, media ingest or loss of private notes")
  assert.call(ActiveJob::Base.queue_adapter.enqueued_jobs.size == existing_jobs, "#{scenario}: repair enqueues no domain side effects")
  attempts = pending.reload.attempts
  job.perform_now(pending.id)
  assert.call(pending.reload.attempts == attempts, "#{scenario}: terminal job repetition does nothing")
end
# rubocop:enable Metrics/BlockLength

puts({ result: 'PASS', checks: checks.size, scenarios: checks }.to_json)
