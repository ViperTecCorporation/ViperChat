require 'rails_helper'
require 'base64'
require 'stringio'

# Exercise the real history importer, contact resolver and provider ingestion.
# Only external media retrieval/storage boundaries are replaced.
# Direct config writes avoid credential checks; legacy identity setup deliberately
# models records created before current E.164 validation. Assertions cover atomic invariants.
# rubocop:disable Rails/SkipsModelValidations, RSpec/AnyInstance, RSpec/MultipleExpectations
RSpec.describe Whatsapp::HistoryImportService do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+5565991234567',
                              sync_templates: false, validate_provider_config: false)
  end
  let!(:contact) { create(:contact, account: account, name: 'Contato antigo', phone_number: '+5565987654321') }
  let!(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: channel.inbox, source_id: '5565987654321') }
  let(:incoming) do
    JSON.parse(Rails.root.join('spec/fixtures/whatsapp_coexistence/meta_phone_incoming.json').read)
        .dig('entry', 0, 'changes', 0, 'value', 'messages', 0)
  end
  let(:outgoing) do
    JSON.parse(Rails.root.join('spec/fixtures/whatsapp_coexistence/meta_phone_echo.json').read)
        .dig('entry', 0, 'changes', 0, 'value', 'message_echoes', 0)
  end
  let(:public_messages) { account.messages.where(message_type: %i[incoming outgoing]) }

  around do |example|
    previous_network_configuration = WebMock::Config.instance.allow_net_connect
    previous_localhost_configuration = WebMock::Config.instance.allow_localhost
    WebMock.disable_net_connect!(allow_localhost: false)
    travel_to(Time.at(1_792_240_000).utc) { example.run }
  ensure
    WebMock::Config.instance.allow_net_connect = previous_network_configuration
    WebMock::Config.instance.allow_localhost = previous_localhost_configuration
  end

  before do
    channel.update_column(:provider_config, channel.provider_config.merge('ignore_history_messages' => false, 'history_max_age_days' => 7))
    allow_any_instance_of(Channel::Whatsapp).to receive(:reauthorization_required?).and_return(false)
  end

  # Batch construction is shared to keep each scenario's message mutations visible.
  def history_payload(messages, chunk: 1, peer: '556587654321')
    history = { 'metadata' => { 'phase' => 1, 'chunk_order' => chunk },
                'threads' => [{ 'id' => peer, 'messages' => messages }] }
    change = { 'field' => 'history', 'value' => { 'history' => [history] } }
    { 'entry' => [{ 'id' => channel.provider_config['business_account_id'], 'changes' => [change] }] }
  end

  def history_event(messages, chunk: 1, peer: '556587654321')
    WhatsappManagementEvent.create!(
      account: account, channel: channel, inbox: channel.inbox, field: 'history',
      digest: Digest::SHA256.hexdigest([chunk, messages].to_json), state: 'pending_import', expires_at: 7.days.from_now,
      payload: history_payload(messages, chunk: chunk, peer: peer)
    )
  end

  def live_payload(provider, kind)
    JSON.parse(Rails.root.join("spec/fixtures/whatsapp_coexistence/#{provider}_#{kind}_incoming.json").read).with_indifferent_access
  end

  # Both arrival-order suites exercise the same external, in-memory download boundary.
  def stub_history_download(url, media)
    allow(Down).to receive(:download).with(url, headers: anything) do
      StringIO.new(media[:bytes]).tap do |io|
        io.define_singleton_method(:original_filename) { media[:filename] }
        io.define_singleton_method(:content_type) { media[:mime] }
      end
    end
  end

  it 'imports through the historical message service without the live lifecycle' do
    payload = live_payload(:meta, 'phone')
    expect do
      Whatsapp::HistoryMessageService.new(inbox: channel.inbox, params: payload).perform
    end.to change(public_messages, :count).by(1)
  end

  it 'imports incoming and outgoing history with original IDs, dates and an already-resolved conversation' do
    event = history_event([incoming, outgoing])
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original
    clear_enqueued_jobs

    described_class.new(event: event).perform

    expect(event.reload).to have_attributes(state: 'processed', reason: nil)
    expect(public_messages.count).to eq(2)
    expect(public_messages.pluck(:source_id)).to contain_exactly(incoming['id'], outgoing['id'])
    expect(public_messages.pluck(:message_type)).to contain_exactly('incoming', 'outgoing')
    public_messages.each do |message|
      expect(message.created_at).to be_within(1.second).of(Time.at(incoming['timestamp'].to_i).utc)
      expect(message.content_attributes['whatsapp_history_import']).to be(true)
    end
    expect(public_messages.incoming.sole.sender).to eq(contact)
    expect(public_messages.outgoing.sole.sender).to be_nil
    expect(account.conversations.sole).to have_attributes(status: 'resolved', waiting_since: nil)
    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with('message.created', anything, anything)
    expect(SendReplyJob).not_to have_been_enqueued
    expect(AgentBots::WebhookJob).not_to have_been_enqueued
    expect(Notification.count).to eq(0)
  end

  it 'preserves an existing conversation state, unread watermarks, activity, assignee and contact identity' do
    conversation = create(:conversation, account: account, inbox: channel.inbox, contact: contact, contact_inbox: contact_inbox,
                                         status: :resolved, agent_last_seen_at: 2.hours.ago, last_activity_at: 3.hours.ago)
    original = conversation.reload.attributes.slice('status', 'last_activity_at', 'agent_last_seen_at', 'channel_agent_last_seen_at',
                                                    'assignee_id', 'team_id', 'waiting_since', 'updated_at')
    original_contact = contact.reload.attributes
    event = history_event([incoming])

    described_class.new(event: event).perform

    expect(public_messages.sole.conversation_id).to eq(conversation.id)
    expect(conversation.reload.attributes.slice(*original.keys)).to eq(original)
    expect(contact.reload.attributes).to eq(original_contact)
    expect(account.contacts.pluck(:id)).to eq([contact.id])
    expect(channel.inbox.contact_inboxes.find_by!(source_id: incoming['from']).contact_id).to eq(contact.id)
  end

  it 'keeps the inclusive seven-day boundary and ignores old, future and malformed timestamps' do
    messages = [-7.days, -7.days - 1.second, 1.second].each_with_index.map do |offset, index|
      incoming.deep_dup.merge('id' => "history-boundary-#{index}", 'timestamp' => (Time.current + offset).to_i.to_s)
    end
    messages << incoming.deep_dup.merge('id' => 'history-invalid', 'timestamp' => 'not-a-date')

    described_class.new(event: history_event(messages)).perform

    expect(public_messages.pluck(:source_id)).to eq(['history-boundary-0'])
  end

  it 'uses a configured period instead of the seven-day default' do
    channel.update_column(:provider_config, channel.provider_config.merge('history_max_age_days' => 2))
    recent = incoming.deep_dup.merge('id' => 'history-recent', 'timestamp' => 1.day.ago.to_i.to_s)
    old = incoming.deep_dup.merge('id' => 'history-old', 'timestamp' => 3.days.ago.to_i.to_s)

    described_class.new(event: history_event([old, recent])).perform

    expect(public_messages.pluck(:source_id)).to eq(['history-recent'])
  end

  it 'does not import or remove existing messages when history is ignored' do
    channel.update_column(:provider_config, channel.provider_config.merge('ignore_history_messages' => true))
    event = history_event([incoming])

    expect { described_class.new(event: event).perform }.not_to change(Message, :count)

    expect(event.reload).to have_attributes(state: 'recorded', reason: 'history_ignored', payload: {})
    expect(account.contacts.pluck(:id)).to eq([contact.id])
  end

  it 'ignores historical group items without skipping an individual item in the same batch' do
    channel.update_column(:provider_config, channel.provider_config.merge('ignore_group_messages' => true))
    group_message = incoming.deep_dup.merge('id' => 'historical-group-ignored', 'group_id' => '120363123456789@g.us')
    event = history_event([group_message, incoming])
    described_class.new(event: event).perform
    expect(event.reload.state).to eq('processed')
    expect(public_messages.pluck(:source_id)).to eq([incoming['id']])
  end

  it 'does not reinterpret an unproven historical group item as a direct conversation' do
    group_message = incoming.deep_dup.merge('id' => 'historical-group-pending', 'group_id' => '120363123456789@g.us')
    event = history_event([group_message])
    expect { described_class.new(event: event).perform }.not_to change(Message, :count)
    expect(event.reload.state).to eq('pending_import')
    expect(account.contacts.count).to eq(1)
  end

  it 'deduplicates both the same batch replay and a new chunk containing the same message' do
    event = history_event([incoming])
    importer = described_class.new(event: event)
    importer.perform
    original = public_messages.sole.attributes

    importer.perform
    second = history_event([incoming], chunk: 2)
    described_class.new(event: second).perform

    expect(public_messages.count).to eq(1)
    expect(public_messages.sole.attributes).to eq(original)
    expect(second.reload.details['duplicate_messages_count']).to eq(1)
    expect(account.contacts.count).to eq(1)
    expect(account.conversations.count).to eq(1)
  end

  it 'advances an imported echo to history_context read and never regresses it on a later delivered chunk' do
    read_echo = outgoing.deep_dup.merge('history_context' => { 'status' => 'read' })
    read_event = history_event([read_echo])
    clear_enqueued_jobs

    described_class.new(event: read_event).perform

    original = public_messages.outgoing.sole
    expect(original).to have_attributes(status: 'read', source_id: outgoing['id'])
    preserved = [original.id, original.source_id, original.created_at, original.conversation_id]
    delivered_echo = outgoing.deep_dup.merge('history_context' => { 'status' => 'delivered' })
    delivered_event = history_event([delivered_echo], chunk: 2)

    described_class.new(event: delivered_event).perform

    expect(delivered_event.reload.state).to eq('processed')
    expect(public_messages.count).to eq(1)
    expect(original.reload.status).to eq('read')
    expect([original.id, original.source_id, original.created_at, original.conversation_id]).to eq(preserved)
    expect(SendReplyJob).not_to have_been_enqueued
  end

  it 'preserves the parent historical timestamp for a shared contact whose card has no timestamp' do
    card = { 'name' => { 'formatted_name' => 'Nome do cartão', 'first_name' => 'Nome' },
             'phones' => [{ 'phone' => '+5565998765432', 'type' => 'CELL' }] }
    message = incoming.deep_dup.except('text').merge('type' => 'contacts', 'contacts' => [card])
    expect(card).not_to have_key('timestamp')
    event = history_event([message])
    original_contact = contact.reload.attributes

    described_class.new(event: event).perform

    imported = public_messages.sole
    expect(event.reload.state).to eq('processed')
    expect(imported).to have_attributes(source_id: message['id'], created_at: Time.zone.at(message['timestamp'].to_i))
    expect(imported.attachments.sole).to have_attributes(file_type: 'contact', fallback_title: '+5565998765432')
    expect(imported.created_at).to be < 12.hours.ago
    expect(contact.reload.attributes).to eq(original_contact)
    expect(account.contacts.pluck(:id)).to eq([contact.id])
  end

  it 'imports official outgoing history without to using the thread peer' do
    message = outgoing.deep_dup.except('to').merge('history_context' => { 'status' => 'READ' })
    event = history_event([message])
    described_class.new(event: event).perform
    expect(event.reload.state).to eq('processed')
    expect(public_messages.outgoing.sole.status).to eq('read')
    expect(public_messages.sole.conversation.contact_id).to eq(contact.id)
  end

  { 'SENT' => 'sent', 'DELIVERED' => 'delivered', 'READ' => 'read', 'PLAYED' => 'read',
    'PENDING' => 'progress', 'ERROR' => 'failed' }.each do |provider_status, expected_status|
    it "normalizes historical #{provider_status} explicitly without dispatching live delivery" do
      message = outgoing.deep_dup.merge('history_context' => { 'status' => provider_status })
      clear_enqueued_jobs
      described_class.new(event: history_event([message])).perform
      expect(public_messages.outgoing.sole.status).to eq(expected_status)
      expect(SendReplyJob).not_to have_been_enqueued
    end
  end

  it 'does not regress READ on later uppercase SENT, DELIVERED, PENDING or ERROR receipts' do
    described_class.new(event: history_event([outgoing.merge('history_context' => { 'status' => 'READ' })])).perform
    %w[SENT DELIVERED PENDING ERROR].each_with_index do |status, index|
      message = outgoing.merge('history_context' => { 'status' => status })
      described_class.new(event: history_event([message], chunk: index + 2)).perform
      expect(public_messages.outgoing.sole.status).to eq('read')
    end
  end

  context 'with an official top-level media follow-up' do
    let(:media_message) do
      live_payload(:meta, 'image').dig(:entry, 0, :changes, 0, :value, :messages, 0).deep_stringify_keys
    end
    let(:followup) do
      params = { 'phone_number' => channel.phone_number,
                 'entry' => [{ 'id' => channel.provider_config['business_account_id'],
                              'changes' => [{ 'field' => 'history', 'value' => { 'messages' => [media_message] } }] }] }
      Whatsapp::ManagementWebhookService.new(params: params).perform.sole
    end

    before do
      media = { filename: 'followup.png', mime: 'image/png',
                bytes: Base64.strict_decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=') }
      url = 'https://history-media.invalid/followup.png'
      stub_request(:get, channel.media_url(media_message.dig('image', 'id')))
        .to_return(status: 200, body: { url: url }.to_json, headers: { 'Content-Type' => 'application/json' })
      stub_history_download(url, media)
      allow(ActiveStorage::Blob.service).to receive(:upload)
    end

    it 'imports and replays media without duplicating a bubble, attachment or blob' do
      event = followup
      described_class.new(event: event).perform
      expect(event.reload.state).to eq('processed')
      preserved = [public_messages.sole.id, Attachment.count, ActiveStorage::Blob.count]
      event.update!(state: 'pending_import')
      described_class.new(event: event).perform
      expect([public_messages.sole.id, Attachment.count, ActiveStorage::Blob.count]).to eq(preserved)
      expect(Down).to have_received(:download).once
    end

    it 'reuses a retained outgoing placeholder context without guessing from the media sender' do
      placeholder = media_message.slice('id', 'timestamp').merge('from' => channel.phone_number.delete_prefix('+'),
                                                              'type' => 'media_placeholder', 'history_context' => { 'status' => 'PLAYED' })
      params = history_payload([placeholder]).merge('phone_number' => channel.phone_number)
      original = Whatsapp::ManagementWebhookService.new(params: params).perform.sole
      described_class.new(event: original).perform
      expect(public_messages).to be_empty
      event = followup
      described_class.new(event: event).perform
      expect(event.reload.state).to eq('processed')
      expect(public_messages.outgoing.sole.status).to eq('read')
      described_class.new(event: original.reload).perform
      expect(original.reload.state).to eq('processed')
      expect(public_messages.count).to eq(1)
      expect(Down).to have_received(:download).once
    end

    it 'keeps a recipientless business media follow-up pending when no context proves the peer' do
      media_message['from'] = channel.phone_number.delete_prefix('+')
      event = followup
      described_class.new(event: event).perform
      expect(event.reload).to have_attributes(state: 'pending_import', reason: 'import_identity_pending')
      expect(public_messages).to be_empty
      expect(Down).not_to have_received(:download)
    end

    it 'treats a peer sender and explicit business recipient as incoming rather than an outgoing echo' do
      media_message['to'] = channel.phone_number.delete_prefix('+')
      media_message['history_context'] = { 'status' => 'READ' }
      event = followup
      described_class.new(event: event).perform
      expect(event.reload.state).to eq('processed')
      expect(public_messages.incoming.sole.conversation.contact_id).to eq(contact.id)
      expect(public_messages.outgoing).to be_empty
      expect(Down).to have_received(:download).once
    end

    it 'does not infer direction when the recipient is neither absent nor the business' do
      media_message['to'] = '16505550000'
      event = followup
      described_class.new(event: event).perform
      expect(event.reload).to have_attributes(state: 'pending_import', reason: 'import_identity_pending')
      expect(public_messages).to be_empty
      expect(Down).not_to have_received(:download)
    end

    it 'normalizes uppercase status on an explicitly addressed outgoing media follow-up' do
      media_message['from'] = channel.phone_number.delete_prefix('+')
      media_message['to'] = incoming['from']
      media_message['history_context'] = { 'status' => 'READ' }
      event = followup
      described_class.new(event: event).perform
      expect(event.reload.state).to eq('processed')
      expect(public_messages.outgoing.sole.status).to eq('read')
      expect(public_messages.sole.conversation.contact_id).to eq(contact.id)
      expect(SendReplyJob).not_to have_been_enqueued
    end

    it 'does not reuse a retained placeholder for a different media sender' do
      placeholder = media_message.slice('id', 'timestamp').merge('from' => incoming['from'], 'type' => 'media_placeholder')
      params = history_payload([placeholder]).merge('phone_number' => channel.phone_number)
      Whatsapp::ManagementWebhookService.new(params: params).perform
      media_message['from'] = '16505550000'
      event = followup
      described_class.new(event: event).perform
      expect(event.reload).to have_attributes(state: 'pending_import', reason: 'import_identity_pending')
      expect(public_messages).to be_empty
      expect(Down).not_to have_received(:download)
    end

    it 'does not reuse context from another link activation or channel' do
      placeholder = media_message.slice('id', 'timestamp').merge('from' => channel.phone_number.delete_prefix('+'), 'type' => 'media_placeholder')
      receipt = history_event([placeholder])
      receipt.update!(details: { 'history_link_id' => 123, 'history_link_activation' => 1.day.ago.iso8601 })
      media_message['from'] = channel.phone_number.delete_prefix('+')
      event = followup
      described_class.new(event: event).perform
      expect(event.reload.state).to eq('pending_import')
      expect(public_messages).to be_empty
      expect(Down).not_to have_received(:download)
    end
  end

  it 'leaves ambiguous eight/nine-digit ownership pending without merging or creating another contact' do
    other = create(:contact, account: account, phone_number: '+5565998765432', name: 'Outro dono estabelecido')
    other.update_column(:phone_number, '+556587654321')
    create(:contact_inbox, inbox: channel.inbox, contact: other, source_id: '556587654321')
    event = history_event([incoming])

    expect { described_class.new(event: event).perform }.not_to change(Message, :count)

    expect(event.reload).to have_attributes(state: 'pending_import', reason: 'import_identity_pending')
    expect(event.details['pending_messages_count']).to eq(1)
    expect(account.contacts.pluck(:id)).to contain_exactly(contact.id, other.id)
    expect(contact_inbox.reload.contact_id).to eq(contact.id)
  end

  it 'deduplicates a history item against the exact message previously received from Meta' do
    payload = live_payload(:meta, 'phone')
    Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: channel.inbox, params: payload).perform
    original = public_messages.sole.attributes

    described_class.new(event: history_event([incoming])).perform

    expect(public_messages.count).to eq(1)
    expect(public_messages.sole.attributes).to eq(original)
    expect(account.contacts.count).to eq(1)
  end

  it 'holds an unknown BSUID without inventing a phone, creating a contact or queuing a live replay' do
    payload = JSON.parse(Rails.root.join('spec/fixtures/whatsapp_coexistence/meta_bsuid_incoming.json').read)
    message = payload.dig('entry', 0, 'changes', 0, 'value', 'messages', 0)
    peer = message.fetch('from_user_id')
    message['from'] = peer
    event = history_event([message], peer: peer)

    described_class.new(event: event).perform

    expect(event.reload).to have_attributes(state: 'pending_import', reason: 'import_identity_pending')
    expect(public_messages).to be_empty
    expect(account.contacts.pluck(:id)).to eq([contact.id])
    expect(WhatsappUnifiedEvent.count).to eq(0)
  end

  it 'leaves media without a provider media ID pending without downloading or creating an empty bubble' do
    message = live_payload(:meta, 'image').dig(:entry, 0, :changes, 0, :value, :messages, 0).deep_stringify_keys
    message['image'].delete('id')
    event = history_event([message])
    allow(Down).to receive(:download).and_raise('Missing media must never download')
    attachment_count = Attachment.count
    blob_count = ActiveStorage::Blob.count

    described_class.new(event: event).perform

    expect(event.reload.state).to eq('pending_import')
    expect(public_messages).to be_empty
    expect(Attachment.count).to eq(attachment_count)
    expect(ActiveStorage::Blob.count).to eq(blob_count)
    expect(Down).not_to have_received(:download)
  end

  it 'rolls back incomplete media while importing the next message, then retries only the missing media' do
    message = live_payload(:meta, 'image').dig(:entry, 0, :changes, 0, :value, :messages, 0).deep_stringify_keys
    following = incoming.deep_dup.merge('id' => 'history-after-incomplete-media', 'timestamp' => (message['timestamp'].to_i + 1).to_s)
    event = history_event([message, following])
    media_endpoint = channel.media_url(message.dig('image', 'id'))
    stub_request(:get, media_endpoint).to_return(status: 503, body: '{}', headers: { 'Content-Type' => 'application/json' })
    attachment_count = Attachment.count
    blob_count = ActiveStorage::Blob.count

    described_class.new(event: event).perform

    expect(event.reload).to have_attributes(state: 'pending_import', reason: 'import_failed')
    expect(public_messages.pluck(:source_id)).to eq([following['id']])
    expect(Attachment.count).to eq(attachment_count)
    expect(ActiveStorage::Blob.count).to eq(blob_count)
    expect(account.conversations.count).to eq(1)
    expect(account.contacts.pluck(:id)).to eq([contact.id])
    preserved = public_messages.sole.attributes
    media = { filename: 'retry.png', mime: 'image/png',
              bytes: Base64.strict_decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=') }
    url = 'https://history-media.invalid/retry.png'
    stub_request(:get, media_endpoint)
      .to_return(status: 200, body: { url: url }.to_json, headers: { 'Content-Type' => 'application/json' })
    stub_history_download(url, media)
    allow(ActiveStorage::Blob.service).to receive(:upload)

    described_class.new(event: event.reload).perform

    expect(event.reload).to have_attributes(state: 'processed', reason: nil)
    expect(public_messages.pluck(:source_id)).to contain_exactly(message['id'], following['id'])
    expect(public_messages.find_by!(source_id: following['id']).attributes).to eq(preserved)
    expect(event.details).to include('pending_messages_count' => 0, 'duplicate_messages_count' => 1)
    expect(Attachment.count - attachment_count).to eq(1)
    expect(ActiveStorage::Blob.count - blob_count).to eq(1)
    expect(Down).to have_received(:download).once
    expect(SendReplyJob).not_to have_been_enqueued
  end

  it 'defers a message under a competing real lease, imports its sibling and succeeds after the lease is released' do
    following = incoming.deep_dup.merge('id' => 'history-after-contended-lease', 'timestamp' => (incoming['timestamp'].to_i + 1).to_s)
    event = history_event([incoming, following])
    lease = Whatsapp::MessageDedupLock.new("#{channel.inbox.id}:#{incoming['id']}")
    expect(lease.acquire!).to be_truthy

    begin
      described_class.new(event: event).perform
      expect(event.reload).to have_attributes(state: 'pending_import', reason: 'import_identity_pending')
      expect(public_messages.pluck(:source_id)).to eq([following['id']])
      lease.ensure_owned!
    ensure
      lease.release!
    end

    described_class.new(event: event.reload).perform
    described_class.new(event: history_event([incoming, following], chunk: 2)).perform

    expect(event.reload.state).to eq('processed')
    expect(public_messages.pluck(:source_id)).to contain_exactly(incoming['id'], following['id'])
    expect(account.conversations.count).to eq(1)
    expect(account.contacts.pluck(:id)).to eq([contact.id])
    expect(SendReplyJob).not_to have_been_enqueued
  end

  context 'with a unified ViperConnect transport' do
    let(:uno_channel) do
      create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: '+556591234567',
                                provider_config: { 'api_key' => 'synthetic', 'url' => 'https://uno.invalid' },
                                sync_templates: false, validate_provider_config: false)
    end

    it 'advances history_context read on a correlated echo without MESSAGE_UPDATED or an agent bot webhook' do
      create(:contact_inbox, inbox: uno_channel.inbox, contact: contact, source_id: '5565987654321')
      WhatsappInboxLink.create!(account: account, primary_inbox: uno_channel.inbox, secondary_inbox: channel.inbox,
                                default_provider: 'unoapi', enabled: true, activated_at: 2.days.ago)
      uno_payload = JSON.parse(Rails.root.join('spec/fixtures/whatsapp_coexistence/uno_phone_echo.json').read).with_indifferent_access
      Whatsapp::IncomingMessageUnoapiService.new(inbox: uno_channel.inbox, params: uno_payload, outgoing_echo: true).perform
      original = public_messages.outgoing.sole
      expect(original.status).to eq('delivered')
      preserved = [original.id, original.source_id, original.created_at, original.conversation_id]
      uno_echo = uno_payload.dig(:entry, 0, :changes, 0, :value, :message_echoes, 0)
      # A durable read receipt can be observed before the importer reconciles it.
      Whatsapp::MessageIdentityObservationService.new(
        inbox: uno_channel.inbox,
        value: { statuses: [{ id: uno_echo[:id], provider_message_id: uno_echo[:provider_message_id],
                              recipient_id: uno_echo[:to], status: 'read', timestamp: Time.current.to_i.to_s }] }.with_indifferent_access
      ).perform
      bot = create(:agent_bot, account: account, outgoing_url: 'https://history-bot.invalid/webhook')
      create(:agent_bot_inbox, inbox: uno_channel.inbox, agent_bot: bot, status: :active)
      event = history_event([outgoing.deep_dup.merge('history_context' => { 'status' => 'read' })])
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original
      clear_enqueued_jobs

      described_class.new(event: event).perform

      expect(event.reload.state).to eq('processed')
      expect(public_messages.count).to eq(1)
      expect(original.reload.status).to eq('read')
      expect([original.id, original.source_id, original.created_at, original.conversation_id]).to eq(preserved)
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with('message.updated', anything, anything)
      expect(AgentBots::WebhookJob).not_to have_been_enqueued
      expect(SendReplyJob).not_to have_been_enqueued
    end

    it 'captures an explicit unlinked receiver snapshot and does not import it into a subsequently enabled pair' do
      params = history_payload([incoming]).merge('phone_number' => channel.phone_number)
      event = Whatsapp::ManagementWebhookService.new(params: params).perform.sole
      expect(event.details).to include('history_link_id' => nil, 'history_link_activation' => nil)
      WhatsappInboxLink.create!(account: account, primary_inbox: uno_channel.inbox, secondary_inbox: channel.inbox,
                                default_provider: 'unoapi', enabled: true)

      described_class.new(event: event).perform

      expect(event.reload.state).to eq('pending_import')
      expect(public_messages).to be_empty
      expect(account.conversations).to be_empty
      expect(WhatsappUnifiedMessage.count).to eq(0)
      expect(WhatsappUnifiedEvent.count).to eq(0)
      expect(account.contacts.pluck(:id)).to eq([contact.id])
    end

    %i[replacement reactivation disabled].each do |administrative_change|
      it "preserves the receiver scope and does not import into another generation after link #{administrative_change}" do
        link = WhatsappInboxLink.create!(account: account, primary_inbox: uno_channel.inbox, secondary_inbox: channel.inbox,
                                         default_provider: 'unoapi', enabled: true)
        params = history_payload([incoming]).merge('phone_number' => channel.phone_number)
        event = Whatsapp::ManagementWebhookService.new(params: params).perform.sole
        snapshot = { 'history_link_id' => link.id, 'history_link_activation' => link.reload.activated_at.iso8601(6) }
        expect(event.details).to include(snapshot)
        expect(described_class.scope_snapshot(channel.inbox)).to eq(snapshot)
        link.update!(enabled: false)
        travel 1.second
        if administrative_change == :replacement
          WhatsappInboxLink.create!(account: account, primary_inbox: channel.inbox, secondary_inbox: uno_channel.inbox,
                                    default_provider: 'whatsapp_cloud', enabled: true)
        elsif administrative_change == :reactivation
          link.update!(enabled: true)
        end

        described_class.new(event: event).perform

        expect(event.reload.state).to eq('pending_import')
        expect(event.details).to include(snapshot)
        expect(public_messages).to be_empty
        expect(account.conversations).to be_empty
        expect(WhatsappUnifiedMessage.count).to eq(0)
        expect(WhatsappUnifiedEvent.count).to eq(0)
        expect(account.contacts.pluck(:id)).to eq([contact.id])
      end
    end

    it 'adopts an exact pre-activation ViperConnect candidate without changing its public ID or creating a second bubble' do
      uno_alias = create(:contact_inbox, inbox: uno_channel.inbox, contact: contact, source_id: '5565987654321')
      payload = live_payload(:uno, 'phone')
      Whatsapp::IncomingMessageUnoapiService.new(inbox: uno_channel.inbox, params: payload).perform
      original = public_messages.sole
      preserved = original.attributes
      WhatsappInboxLink.create!(account: account, primary_inbox: uno_channel.inbox, secondary_inbox: channel.inbox,
                                default_provider: 'unoapi', enabled: true, activated_at: Time.current)

      event = history_event([incoming])
      described_class.new(event: event).perform

      expect(event.reload.state).to eq('processed')
      expect(public_messages.count).to eq(1)
      expect(original.reload.attributes).to eq(preserved)
      identity = WhatsappMessageIdentity.find_by!(inbox: channel.inbox, external_id: incoming['id'])
      expect(Whatsapp::UnifiedMessageIngestionService.message_for(identity).id).to eq(original.id)
      expect(uno_alias.reload.contact_id).to eq(contact.id)
      expect(account.contacts.count).to eq(1)
    end

    it 'resolves the real BSUID wamid through the ViperConnect message instead of inventing another contact' do
      create(:contact_inbox, inbox: uno_channel.inbox, contact: contact, source_id: '5565987654321')
      uno_payload = JSON.parse(Rails.root.join('spec/fixtures/whatsapp_coexistence/uno_bsuid_incoming.json').read).with_indifferent_access
      Whatsapp::IncomingMessageUnoapiService.new(inbox: uno_channel.inbox, params: uno_payload).perform
      original = public_messages.sole
      preserved = [original.id, original.source_id, original.conversation_id, original.sender_id]
      WhatsappInboxLink.create!(account: account, primary_inbox: uno_channel.inbox, secondary_inbox: channel.inbox,
                                default_provider: 'unoapi', enabled: true, activated_at: Time.current)
      meta_payload = JSON.parse(Rails.root.join('spec/fixtures/whatsapp_coexistence/meta_bsuid_incoming.json').read)
      message = meta_payload.dig('entry', 0, 'changes', 0, 'value', 'messages', 0)
      peer = message.fetch('from_user_id')
      message['from'] = peer
      event = history_event([message], peer: peer)

      described_class.new(event: event).perform

      expect(event.reload.state).to eq('processed')
      expect(public_messages.count).to eq(1)
      expect([original.reload.id, original.source_id, original.conversation_id, original.sender_id]).to eq(preserved)
      expect(account.contacts.pluck(:id)).to eq([contact.id])
      expect(WhatsappUnifiedEvent.count).to eq(0)
      identity = WhatsappMessageIdentity.find_by!(inbox: channel.inbox, external_id: message['id'])
      expect(Whatsapp::UnifiedMessageIngestionService.message_for(identity)).to eq(original)
    end
  end

  media_formats = [
    { kind: 'image', filename: 'synthetic.png', mime: 'image/png',
      bytes: Base64.strict_decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=') },
    { kind: 'audio', filename: 'synthetic.wav', mime: 'audio/x-wav',
      bytes: ['524946462600000057415645666d74201000000001000100401f0000803e00000200100064617461020000000000'].pack('H*') },
    { kind: 'document', filename: 'synthetic.pdf', mime: 'application/pdf', bytes: "%PDF-1.4\n%%EOF\n" }
  ]

  media_formats.each do |media|
    it "imports #{media[:kind]} once across chunks, preserving one attachment/blob and downloading only once" do
      message = live_payload(:meta, media[:kind]).dig(:entry, 0, :changes, 0, :value, :messages, 0).deep_stringify_keys
      media_id = message.fetch(media[:kind]).fetch('id')
      url = "https://history-media.invalid/#{media[:filename]}"
      stub_request(:get, channel.media_url(media_id))
        .to_return(status: 200, body: { url: url }.to_json, headers: { 'Content-Type' => 'application/json' })
      stub_history_download(url, media)
      allow(ActiveStorage::Blob.service).to receive(:upload)
      attachment_count = Attachment.count
      blob_count = ActiveStorage::Blob.count

      described_class.new(event: history_event([message])).perform
      original = public_messages.sole
      preserved = [original.id, original.source_id, original.attachments.sole.id, original.attachments.sole.file.blob_id]
      described_class.new(event: history_event([message], chunk: 2)).perform
      Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: channel.inbox, params: live_payload(:meta, media[:kind])).perform

      expect(public_messages.count).to eq(1)
      expect(Attachment.count - attachment_count).to eq(1)
      expect(ActiveStorage::Blob.count - blob_count).to eq(1)
      expect(Down).to have_received(:download).once
      expect(ActiveStorage::Blob.service).to have_received(:upload).once
      expect([original.reload.id, original.source_id, original.attachments.sole.id, original.attachments.sole.file.blob_id]).to eq(preserved)
      expect(original.attachments.sole.file.blob).to have_attributes(content_type: media[:mime], byte_size: media[:bytes].bytesize)
      expect(original.conversation).to be_resolved
      expect(SendReplyJob).not_to have_been_enqueued
    end
  end

  context 'when history media arrives before its ViperConnect counterpart' do
    let(:uno_channel) do
      create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: '+556591234567',
                                provider_config: { 'api_key' => 'synthetic', 'url' => 'https://uno.invalid' },
                                sync_templates: false, validate_provider_config: false)
    end

    media_formats.each do |media|
      it "deduplicates the later #{media[:kind]} webhook before a second download, preserving historical IDs and media" do
        create(:contact_inbox, inbox: uno_channel.inbox, contact: contact, source_id: '5565987654321')
        WhatsappInboxLink.create!(account: account, primary_inbox: uno_channel.inbox, secondary_inbox: channel.inbox,
                                  default_provider: 'unoapi', enabled: true, activated_at: Time.current)
        message = live_payload(:meta, media[:kind]).dig(:entry, 0, :changes, 0, :value, :messages, 0).deep_stringify_keys
        params = history_payload([message]).merge('phone_number' => channel.phone_number)
        params['entry'].first['changes'].first['value'] = { 'messages' => [message] }
        event = Whatsapp::ManagementWebhookService.new(params: params).perform.sole
        url = "https://history-media.invalid/first-#{media[:filename]}"
        stub_request(:get, channel.media_url(message.dig(media[:kind], 'id')))
          .to_return(status: 200, body: { url: url }.to_json, headers: { 'Content-Type' => 'application/json' })
        stub_history_download(url, media)
        allow(ActiveStorage::Blob.service).to receive(:upload)
        attachment_count = Attachment.count
        blob_count = ActiveStorage::Blob.count

        described_class.new(event: event).perform
        expect(event.reload.state).to eq('processed')
        original = public_messages.sole
        preserved = [original.id, original.source_id, original.conversation_id,
                     original.attachments.sole.id, original.attachments.sole.file.blob_id]
        uno_payload = live_payload(:uno, media[:kind])
        2.times { Whatsapp::IncomingMessageUnoapiService.new(inbox: uno_channel.inbox, params: uno_payload.deep_dup).perform }
        described_class.new(event: history_event([message], chunk: 2)).perform

        expect(public_messages.count).to eq(1)
        expect(original.reload.inbox_id).to eq(uno_channel.inbox.id)
        expect([original.id, original.source_id, original.conversation_id,
                original.attachments.sole.id, original.attachments.sole.file.blob_id]).to eq(preserved)
        expect(Attachment.count - attachment_count).to eq(1)
        expect(ActiveStorage::Blob.count - blob_count).to eq(1)
        expect(Down).to have_received(:download).once
        expect(ActiveStorage::Blob.service).to have_received(:upload).once
        uno_id = uno_payload.dig(:entry, 0, :changes, 0, :value, :messages, 0, :id)
        identity = WhatsappMessageIdentity.find_by!(inbox: uno_channel.inbox, external_id: uno_id)
        expect(Whatsapp::UnifiedMessageIngestionService.message_for(identity)).to eq(original)
        expect(account.contacts.pluck(:id)).to eq([contact.id])
        expect(SendReplyJob).not_to have_been_enqueued
      end
    end
  end
end
# rubocop:enable Rails/SkipsModelValidations, RSpec/AnyInstance, RSpec/MultipleExpectations
