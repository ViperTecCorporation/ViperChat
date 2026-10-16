unless Rails.env.test? && ActiveRecord::Base.connection_db_config.database == 'viperchat_provider_identity_test'
  raise 'Wrong database: refusing validation'
end

require 'webmock'
WebMock.enable!
WebMock.disable_net_connect!
ActiveJob::Base.queue_adapter = :test
require 'factory_bot_rails'
FactoryBot.find_definitions unless FactoryBot.factories.registered?(:account)

checks = []
assert = lambda { |condition, label|
  raise "FAILED: #{label}" unless condition

  checks << label
}
channel = FactoryBot.create(:channel_whatsapp, provider: 'unoapi', sync_templates: false, validate_provider_config: false)
inbox = channel.inbox
value = {
  messaging_product: 'whatsapp', metadata: { phone_number_id: channel.phone_number },
  contacts: [{ wa_id: '5511999999999', profile: { name: 'Provider identity test' } }],
  messages: [{ from: '5511999999999', id: 'uno-first', provider_message_id: 'ProtocolCaseSensitive',
               type: 'text', text: { body: 'Local fixture' }, timestamp: '1792110000' }]
}.with_indifferent_access
service = Whatsapp::IncomingMessageUnoapiService
service.new(inbox: inbox, params: value).perform
message = inbox.messages.find_by!(source_id: 'uno-first')
identity = WhatsappMessageIdentity.find_by!(inbox: inbox, external_id: 'uno-first')
assert.call(identity.provider_message_id == 'ProtocolCaseSensitive', 'opaque original ID persisted')
assert.call(identity.messages.pluck(:id) == [message.id], 'received message association')
assert.call(identity.account_id == inbox.account_id && identity.channel_id == channel.id, 'account/channel scope')
before_count = inbox.messages.count
service.new(inbox: inbox, params: value).perform
assert.call(inbox.messages.count == before_count && identity.message_links.count == 1, 'repeated webhook has no extra bubbles or links')
assert.call(message.reload.source_id == 'uno-first', 'source_id unchanged')

legacy = value.deep_dup
legacy[:messages][0].delete(:provider_message_id)
legacy[:messages][0][:id] = 'uno-legacy'
service.new(inbox: inbox, params: legacy).perform
assert.call(inbox.messages.exists?(source_id: 'uno-legacy'), 'old payload remains accepted')
assert.call(!WhatsappMessageIdentity.exists?(inbox: inbox, external_id: 'uno-legacy'), 'no invented original identity for old events')

status = { statuses: [{ id: 'uno-early', provider_message_id: 'OriginalEarly', status: 'read', timestamp: '1792110001' }] }
service.new(inbox: inbox, params: status.with_indifferent_access).perform
pending = WhatsappMessageIdentity.find_by!(inbox: inbox, external_id: 'uno-early')
assert.call(pending.messages.empty?, 'status before message retained without bubble')
early = legacy.deep_dup
early[:messages][0][:id] = 'uno-early'
service.new(inbox: inbox, params: early).perform
assert.call(pending.messages.count == 1 && pending.reload.provider_message_id == 'OriginalEarly', 'pending status linked when legacy message arrives')
assert.call(pending.observations.dig('statuses', 'read') == '1792110001', 'raw status timestamp retained')

quote = value.deep_dup
quote[:messages][0].merge!(id: 'uno-quote', provider_message_id: 'OriginalQuote',
                           context: { id: 'uno-first', message_id: 'uno-first', provider_message_id: 'ProtocolCaseSensitive' })
service.new(inbox: inbox, params: quote).perform
quoted = WhatsappMessageIdentity.find_by!(inbox: inbox, external_id: 'uno-quote')
assert.call(quoted.observations.dig('context', 'provider_message_id') == 'ProtocolCaseSensitive', 'quoted original belongs to context, not event')
assert.call(quoted.provider_message_id == 'OriginalQuote', 'event and quoted target remain distinct')
assert.call(inbox.messages.find_by!(source_id: 'uno-quote').content_attributes['in_reply_to_external_id'] == 'uno-first',
            'quote keeps existing operational reference')

conflict = value.deep_dup
conflict[:messages][0][:provider_message_id] = 'ConflictingOriginal'
service.new(inbox: inbox, params: conflict).perform
identity.reload
assert.call(identity.provider_message_id == 'ProtocolCaseSensitive', 'conflict never overwrites known identity')
assert.call(identity.observations['conflicting_provider_message_ids'] == ['ConflictingOriginal'], 'conflict retained for observation')

conversation = message.conversation
optimistic = FactoryBot.create(:message, account: inbox.account, inbox: inbox, conversation: conversation,
                                         source_id: nil, message_type: :outgoing, status: :progress)
observer = Whatsapp::MessageIdentityObservationService
observer.new(inbox: inbox,
             value: { statuses: [{ id: 'uno-send', provider_message_id: 'OriginalSend', status: 'sent',
                                   timestamp: '1792110002' }] }).perform
optimistic.update!(source_id: 'uno-send')
assert.call(optimistic.whatsapp_message_identities.first.provider_message_id == 'OriginalSend', 'late API source assignment links early status')
echo = { message_echoes: [{ id: 'uno-send', provider_message_id: 'OriginalSend', to: '5511999999999',
                            from: channel.phone_number, type: 'text', text: { body: 'Local echo' },
                            timestamp: '1792110002' }] }.with_indifferent_access
before_count = inbox.messages.count
service.new(inbox: inbox, params: echo, outgoing_echo: true).perform
assert.call(inbox.messages.count == before_count, 'echo reuses optimistic message without duplicate')
assert.call(optimistic.whatsapp_message_identities.first.observations['direction'] == 'outgoing', 'echo direction retained')

phone_echo = value.deep_dup
phone_echo[:metadata][:display_phone_number] = channel.phone_number
phone_echo[:messages][0].merge!(id: 'uno-phone-echo', provider_message_id: 'OriginalPhoneEcho', from: channel.phone_number.delete_prefix('+'))
service.new(inbox: inbox, params: phone_echo).perform
phone_identity = WhatsappMessageIdentity.find_by!(inbox: inbox, external_id: 'uno-phone-echo')
assert.call(phone_identity.observations['direction'] == 'outgoing', 'generic messages echo matches existing direction resolver')
assert.call(inbox.messages.find_by!(source_id: 'uno-phone-echo').outgoing?, 'generic echo remains outgoing in legacy model')

contact_copy = FactoryBot.create(:message, account: inbox.account, inbox: inbox, conversation: conversation,
                                           source_id: 'uno-first', message_type: :incoming)
assert.call(identity.message_links.reload.pluck(:message_id).sort == [message.id, contact_copy.id].sort,
            'one transport identity may link multiple legacy contact bubbles')

other = FactoryBot.create(:channel_whatsapp, provider: 'unoapi', sync_templates: false, validate_provider_config: false)
observer.new(inbox: other.inbox, value: value).perform
other_identity = WhatsappMessageIdentity.find_by!(inbox: other.inbox, external_id: 'uno-first')
assert.call(other_identity.id != identity.id && other_identity.messages.empty?, 'same external ID isolated between accounts/inboxes')
invalid = WhatsappMessageIdentityLink.new(whatsapp_message_identity: other_identity, message: message)
assert.call(!invalid.valid?, 'cross-account message link rejected')

threads = Array.new(2) do
  Thread.new do
    ActiveRecord::Base.connection_pool.with_connection do
      observer.new(inbox: inbox, value: { statuses: [{ id: 'uno-concurrent', provider_message_id: 'OriginalConcurrent', status: 'read' }] }).perform
    end
  end
end
threads.each(&:value)
assert.call(WhatsappMessageIdentity.where(inbox: inbox, external_id: 'uno-concurrent').count == 1, 'concurrent observation has one identity')

meta = FactoryBot.create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
wamid = 'wamid.HBgMNTU2Njk2MjY5MjUxFQIAEhgUM0E4NkEzQUM3QzFDN0JDRTM4ODEA'
observer.new(inbox: meta.inbox, value: { statuses: [{ id: wamid, status: 'read', timestamp: '1792110003' }] }).perform
meta_identity = WhatsappMessageIdentity.find_by!(inbox: meta.inbox, external_id: wamid)
assert.call(meta_identity.provider_message_id.nil?, 'Meta raw ID retained without speculative decoding')
assert.call(meta_identity.external_id == wamid, 'full wamid unchanged')

observer.new(inbox: inbox,
             value: { statuses: [{ id: 'uno-first', provider_message_id: 'ProtocolCaseSensitive', status: 'deleted',
                                   timestamp: '1792110004' }] }).perform
assert.call(identity.reload.observations.dig('statuses', 'deleted') == '1792110004', 'deletion identity refers to existing target')
observer.new(inbox: inbox, value: {
               messages: [{ id: 'uno-edit-event', provider_message_id: 'OriginalEditEvent', type: 'text',
                            message_type: 'message_edit', edit_timestamp: 1_792_110_005_000,
                            context: { id: 'uno-first', provider_message_id: 'ProtocolCaseSensitive' },
                            text: { body: 'not persisted in observations' } }]
             }).perform
edit = WhatsappMessageIdentity.find_by!(inbox: inbox, external_id: 'uno-edit-event')
assert.call(edit.observations['event_type'] == 'message_edit' && edit.observations['edit_timestamp'] == 1_792_110_005_000,
            'edit event type and raw timestamp retained')
assert.call(edit.messages.empty? && edit.provider_message_id == 'OriginalEditEvent', 'unrendered edit event is not an alias for target message')
assert.call(edit.observations.to_json.exclude?('not persisted in observations'), 'observation never stores message body')
observer.new(inbox: inbox, value: {
               messages: [{ id: 'uno-reaction-event', provider_message_id: 'OriginalReactionEvent', type: 'reaction',
                            reaction: { message_id: 'uno-first', provider_message_id: 'ProtocolCaseSensitive', emoji: '👍' } }]
             }).perform
reaction = WhatsappMessageIdentity.find_by!(inbox: inbox, external_id: 'uno-reaction-event')
assert.call(reaction.observations.dig('reaction', 'provider_message_id') == 'ProtocolCaseSensitive',
            'reaction target kept separate from reaction event')
assert.call(!WhatsappMessageIdentity.new.valid?, 'incomplete identity returns validation errors instead of exception')
assert.call(!WhatsappMessageIdentityLink.new.valid?, 'incomplete link returns validation errors instead of exception')

message_count = Message.count
load Rails.root.join('db/migrate/20261016000000_create_whatsapp_message_identities.rb')
ActiveRecord::Migration.suppress_messages { CreateWhatsappMessageIdentities.new.migrate(:down) }
assert.call(!ActiveRecord::Base.connection.data_source_exists?(:whatsapp_message_identities),
            'isolated migration down removes new observation tables')
assert.call(Message.count == message_count, 'migration rollback does not remove legacy messages')
ActiveRecord::Migration.suppress_messages { CreateWhatsappMessageIdentities.new.migrate(:up) }
assert.call(ActiveRecord::Base.connection.data_source_exists?(:whatsapp_message_identity_links), 'isolated migration can be reapplied')

# Machine-readable CLI report, not an application log.
puts({ result: 'PASS', database: ActiveRecord::Base.connection_db_config.database, checks: checks.size, scenarios: checks }.to_json) # rubocop:disable Rails/Output
