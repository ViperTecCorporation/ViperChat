require 'rails_helper'

RSpec.describe Whatsapp::UnifiedDeliveryStateService do
  let(:account) { create(:account) }
  let(:uno) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: '+5565996222471',
                              provider_config: { 'api_key' => 'synthetic', 'url' => 'https://uno.invalid', 'phone_number_id' => 'synthetic' },
                              sync_templates: false, validate_provider_config: false)
  end
  let(:meta) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+556596222471',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:conversation) { create(:conversation, inbox: uno.inbox, account: account) }
  let(:message) do
    link = WhatsappInboxLink.create!(account: account, primary_inbox: uno.inbox, secondary_inbox: meta.inbox,
                                     default_provider: 'unoapi', enabled: true)
    create(:message, account: account, inbox: uno.inbox, conversation: conversation, message_type: :outgoing, status: :progress,
                     content: 'Synthetic disconnected-session check', content_attributes: {
                       whatsapp_transport: { link_id: link.id, activation_cutoff: link.activated_at.iso8601(6), requested_provider: 'unoapi',
                                             provider: 'unoapi', inbox_id: uno.inbox.id, capability: 'text', reason: 'selected' }
                     })
  end

  before do
    WebMock.disable_net_connect!(allow_localhost: false)
    create(:contact_inbox, inbox: meta.inbox, contact: conversation.contact, source_id: '5565987654321')
    conversation.contact_inbox.update!(source_id: '5565987654321')
    create(:message, account: account, inbox: meta.inbox, conversation: conversation,
                     sender: conversation.contact, message_type: :incoming)
  end

  it 'retries a definitive UnoAPI rejection once on Meta in the same bubble and retains both outcomes', :aggregate_failures do
    outgoing = message
    ids = [outgoing.id, outgoing.conversation_id, outgoing.inbox_id, conversation.contact_id]
    uno_request = stub_request(:post, uno.provider_service.send(:messages_path)).to_return(
      status: 409, body: { error: { message: '409: Sessão desconectada', code: 409 } }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )
    meta_request = stub_request(:post, meta.provider_service.send(:messages_path)).to_return(
      status: 200, body: { messages: [{ id: 'wamid.synthetic-fallback' }] }.to_json, headers: { 'Content-Type' => 'application/json' }
    )
    original_counts = [account.messages.count, account.conversations.count, account.contacts.count, Attachment.count, ActiveStorage::Blob.count]
    clear_enqueued_jobs

    Whatsapp::SendOnWhatsappService.new(message: outgoing).perform
    expect(outgoing.reload.content_attributes.dig('whatsapp_transport', 'fallback_pending')).to be(true)
    expect(enqueued_jobs.count { |job| job[:job] == SendReplyJob }).to eq(1)
    2.times { Whatsapp::SendOnWhatsappService.new(message: outgoing.reload).perform }
    described_class.new(message: outgoing, inbox: meta.inbox).record(state: 'delivered', source_id: 'wamid.synthetic-fallback')

    expect(uno_request).to have_been_requested.once
    expect(meta_request).to have_been_requested.once
    expect(outgoing.reload.content_attributes.dig('whatsapp_delivery', 'unoapi')).to include('state' => 'failed', 'code' => 409)
    expect(outgoing.content_attributes.dig('whatsapp_delivery', 'whatsapp_cloud', 'state')).to eq('delivered')
    expect(outgoing).to have_attributes(status: 'delivered', external_error: nil)
    expect([outgoing.id, outgoing.conversation_id, outgoing.inbox_id, conversation.contact_id]).to eq(ids)
    expect([account.messages.count, account.conversations.count, account.contacts.count, Attachment.count,
            ActiveStorage::Blob.count]).to eq(original_counts)
  end

  it 'preserves an accepted queue ID and adds the alternate alias after a later failed receipt', :aggregate_failures do
    outgoing = message
    stub_request(:post, uno.provider_service.send(:messages_path)).to_return(
      status: 200, body: { messages: [{ id: 'synthetic-original-queue-id' }] }.to_json, headers: { 'Content-Type' => 'application/json' }
    )
    meta_request = stub_request(:post, meta.provider_service.send(:messages_path)).to_return(
      status: 200, body: { messages: [{ id: 'wamid.synthetic-alternate' }] }.to_json, headers: { 'Content-Type' => 'application/json' }
    )
    Whatsapp::SendOnWhatsappService.new(message: outgoing).perform
    receipt = { id: outgoing.reload.source_id, status: 'failed', errors: [{ code: 409, title: 'Sessão desconectada' }] }.with_indifferent_access
    receiver = Whatsapp::IncomingMessageBaseService.new(inbox: uno.inbox, params: {})
    2.times { receiver.send(:update_message_with_status, outgoing.reload, receipt) }
    2.times { Whatsapp::SendOnWhatsappService.new(message: outgoing.reload).perform }

    expect(meta_request).to have_been_requested.once
    expect(outgoing.reload.source_id).to eq('synthetic-original-queue-id')
    expect(outgoing.content_attributes.dig('whatsapp_transport', 'provider_source_id')).to eq('wamid.synthetic-alternate')
    expect(Whatsapp::UnifiedTransportService.new(message: outgoing).reference_for(outgoing)).to eq('wamid.synthetic-alternate')
    expect(WhatsappMessageIdentity.where(account: account, inbox: meta.inbox, external_id: 'wamid.synthetic-alternate')).to exist
    expect(Whatsapp::IncomingMessageBaseService.new(inbox: meta.inbox, params: {}).send(:find_message_by_source_id,
                                                                                        'wamid.synthetic-alternate')).to eq(outgoing)
    described_class.new(message: outgoing, inbox: meta.inbox).record(state: 'read', source_id: 'wamid.synthetic-alternate')
    conversation.resolved!
    receiver.send(:update_message_with_status, outgoing.reload, receipt)
    expect(outgoing.reload).to have_attributes(status: 'read', external_error: nil)
    expect(conversation.reload).to be_resolved
  end

  [408, 500, 502].each do |code|
    it "never switches providers after uncertain HTTP #{code}" do
      outgoing = message
      request = stub_request(:post, uno.provider_service.send(:messages_path)).to_return(
        status: code, body: { error: { message: 'Synthetic uncertain upstream result' } }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
      clear_enqueued_jobs
      Whatsapp::SendOnWhatsappService.new(message: outgoing).perform
      expect(request).to have_been_requested.once
      expect(outgoing.reload.content_attributes.dig('whatsapp_transport', 'provider')).to eq('unoapi')
      expect(outgoing.content_attributes.dig('whatsapp_delivery', 'unoapi', 'state')).to eq('uncertain')
      expect(enqueued_jobs.none? { |job| job[:job] == SendReplyJob }).to be(true)
    end
  end

  it 'stops after both providers reject, with no ping-pong or new bubble' do
    outgoing = message
    [uno, meta].each do |channel|
      stub_request(:post, channel.provider_service.send(:messages_path)).to_return(
        status: 400, body: { error: { message: 'Synthetic rejection', code: 400 } }.to_json, headers: { 'Content-Type' => 'application/json' }
      )
    end
    clear_enqueued_jobs
    2.times { Whatsapp::SendOnWhatsappService.new(message: outgoing.reload).perform }
    described_class.new(message: outgoing).prepare_fallback
    expect(outgoing.reload.status).to eq('failed')
    expect(outgoing.content_attributes.fetch('whatsapp_delivery').values.pluck('state')).to eq(%w[failed failed])
    expect(enqueued_jobs.count { |job| job[:job] == SendReplyJob }).to eq(1)
  end

  it 'also falls back from an explicitly selected Meta transport to UnoAPI' do
    outgoing = message
    attrs = outgoing.content_attributes.deep_dup
    attrs['whatsapp_transport'].merge!('provider' => 'whatsapp_cloud', 'requested_provider' => 'whatsapp_cloud', 'inbox_id' => meta.inbox.id)
    outgoing.update!(content_attributes: attrs)
    meta_request = stub_request(:post, meta.provider_service.send(:messages_path)).to_return(
      status: 400, body: { error: { message: 'Synthetic definitive Meta rejection', code: 131_000 } }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )
    uno_request = stub_request(:post, uno.provider_service.send(:messages_path)).to_return(
      status: 200, body: { messages: [{ id: 'synthetic-uno-alternate' }] }.to_json, headers: { 'Content-Type' => 'application/json' }
    )
    2.times { Whatsapp::SendOnWhatsappService.new(message: outgoing.reload).perform }
    expect(meta_request).to have_been_requested.once
    expect(uno_request).to have_been_requested.once
    expect(outgoing.reload.content_attributes.dig('whatsapp_transport', 'requested_provider')).to eq('whatsapp_cloud')
    expect(outgoing.content_attributes.dig('whatsapp_delivery', 'whatsapp_cloud', 'state')).to eq('failed')
    expect(outgoing.content_attributes.dig('whatsapp_delivery', 'unoapi', 'state')).to eq('sent')
  end

  it 'retains existing attachments, blobs and their IDs while switching providers' do
    outgoing = message
    attachment = outgoing.attachments.create!(account_id: account.id, file_type: :image)
    attachment.file.attach(io: StringIO.new('synthetic image content'), filename: 'synthetic.png', content_type: 'image/png')
    inventory = [attachment.id, attachment.file.attachment.id, attachment.file.blob.id, attachment.file.blob.key]
    attrs = outgoing.content_attributes.deep_dup
    attrs['whatsapp_transport']['capability'] = 'image'
    outgoing.update!(content_attributes: attrs)
    uno_request = stub_request(:post, uno.provider_service.send(:messages_path)).to_return(
      status: 409, body: { error: { message: 'Disconnected', code: 409 } }.to_json, headers: { 'Content-Type' => 'application/json' }
    )
    meta_request = stub_request(:post, meta.provider_service.send(:messages_path))
                   .with { |sent| JSON.parse(sent.body)['type'] == 'image' && JSON.parse(sent.body).dig('image', 'link').present? }
                   .to_return(status: 200, body: { messages: [{ id: 'wamid.synthetic-media' }] }.to_json,
                              headers: { 'Content-Type' => 'application/json' })
    2.times { Whatsapp::SendOnWhatsappService.new(message: outgoing.reload).perform }
    attachment.reload
    expect([attachment.id, attachment.file.attachment.id, attachment.file.blob.id, attachment.file.blob.key]).to eq(inventory)
    expect(outgoing.reload.attachments.ids).to eq([attachment.id])
    expect(uno_request).to have_been_requested.once
    expect(meta_request).to have_been_requested.once
  end

  it 'recovers only a pending unclaimed alternate, never an uncertain request' do
    outgoing = message
    described_class.new(message: outgoing).record(state: 'failed', error: 'Disconnected', confirmed_failure: true)
    travel 1.minute do
      clear_enqueued_jobs
      Whatsapp::RecoverPendingFallbacksJob.perform_now
      expect(enqueued_jobs.count { |job| job[:job] == SendReplyJob }).to eq(1)
      outgoing.reload
      attrs = outgoing.content_attributes.deep_dup
      attrs['whatsapp_transport'].merge!('fallback_pending' => false, 'delivery_state' => 'uncertain', 'delivery_attempt_id' => SecureRandom.uuid)
      outgoing.update!(content_attributes: attrs)
      travel 1.minute
      clear_enqueued_jobs
      Whatsapp::RecoverPendingFallbacksJob.perform_now
      expect(enqueued_jobs.none? { |job| job[:job] == SendReplyJob }).to be(true)
    end
  end

  it 'blocks Meta outside the reply window instead of sending a free-form message' do
    outgoing = message
    conversation.messages.incoming.each { |incoming| incoming.update!(created_at: 2.days.ago) }
    described_class.new(message: outgoing).record(state: 'failed', error: 'Disconnected', confirmed_failure: true)
    expect(outgoing.reload.content_attributes.dig('whatsapp_transport', 'fallback_blocked_reason')).to eq('template_required')
    expect(outgoing.content_attributes.dig('whatsapp_transport', 'provider')).to eq('unoapi')
  end

  it 'recovers a definitive rejection persisted before the alternate could be prepared' do
    outgoing = message
    attrs = outgoing.content_attributes.deep_dup
    attrs['whatsapp_transport'].merge!('delivery_state' => 'failed', 'delivery_attempt_id' => SecureRandom.uuid)
    attrs['whatsapp_delivery'] = { 'unoapi' => { 'state' => 'failed', 'confirmed_failure' => true, 'error' => 'Disconnected' } }
    outgoing.update!(status: :failed, content_attributes: attrs)
    travel 1.minute do
      clear_enqueued_jobs
      Whatsapp::RecoverPendingFallbacksJob.perform_now
      expect(enqueued_jobs.count { |job| job[:job] == SendReplyJob }).to eq(1)
      expect(outgoing.reload.content_attributes.dig('whatsapp_transport', 'fallback_pending')).to be(true)
      expect(outgoing.content_attributes.dig('whatsapp_transport', 'provider')).to eq('whatsapp_cloud')
    end
  end

  it 'does not route an unsupported capability to Meta' do
    outgoing = message
    attrs = outgoing.content_attributes.deep_dup
    attrs['whatsapp_transport']['capability'] = 'pix'
    outgoing.update!(content_attributes: attrs)
    described_class.new(message: outgoing).record(state: 'failed', error: 'Disconnected', confirmed_failure: true)
    expect(outgoing.reload.content_attributes.dig('whatsapp_transport', 'fallback_blocked_reason')).to eq('unsupported')
  end

  it 'retains UnoAPI warnings while recording a linked failed receipt and preparing the alternate' do
    outgoing = message
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original
    outgoing.update!(source_id: 'synthetic-warning-source')
    params = { entry: [{ changes: [{ value: { statuses: [{ id: outgoing.source_id, status: 'failed',
                                                           errors: [{ code: 409, title: 'Disconnected' }],
                                                           warnings: [{ code: 'VIDEO_TRANSCODED', message: 'Converted video' }] }] } }] }] }
    Whatsapp::IncomingMessageUnoapiService.new(inbox: uno.inbox, params: params.with_indifferent_access).perform
    expect(outgoing.reload.content_attributes.dig('whatsapp_transport', 'fallback_pending')).to be(true)
    expect(outgoing.content_attributes['unoapi_warnings'].pluck('code')).to eq(['VIDEO_TRANSCODED'])
    expect(outgoing.source_id).to eq('synthetic-warning-source')
    expect(Rails.configuration.dispatcher).to have_received(:dispatch).with('message.updated', anything, anything).at_least(:once)
  end

  it 'broadcasts a linked UnoAPI delivery receipt so the UI updates without a refresh' do
    outgoing = message
    outgoing.update!(source_id: 'synthetic-delivery-source')
    updates = []
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_wrap_original do |original, event, time, data|
      updates << data[:message].push_event_data.deep_dup if event == 'message.updated'
      original.call(event, time, data)
    end
    params = { entry: [{ changes: [{ value: { statuses: [{ id: outgoing.source_id, status: 'delivered' }] } }] }] }
    Whatsapp::IncomingMessageUnoapiService.new(inbox: uno.inbox, params: params.with_indifferent_access).perform
    expect(updates).to include(hash_including(status: 'delivered', content_attributes: hash_including(
      'whatsapp_delivery' => hash_including('unoapi' => hash_including('state' => 'delivered'))
    )))
  end

  it 'cancels a pending alternate attempt if the original confirms delivery before the claim' do
    outgoing = message
    state = described_class.new(message: outgoing)
    state.record(state: 'failed', error: 'Disconnected', confirmed_failure: true)
    state.record(state: 'delivered', source_id: 'synthetic-late-original')
    expect(outgoing.reload).to have_attributes(status: 'delivered', external_error: nil)
    expect(outgoing.content_attributes.dig('whatsapp_transport', 'fallback_pending')).to be(false)
    expect(outgoing.content_attributes.dig('whatsapp_transport', 'provider')).to eq('unoapi')
    expect(outgoing.content_attributes.dig('whatsapp_delivery', 'whatsapp_cloud', 'state')).to eq('skipped')
  end

  it 'does not treat a partner echo as delivered or send again after observing the same bubble there' do
    outgoing = message
    described_class.new(message: outgoing, inbox: meta.inbox).record(state: 'delivered', source_id: 'wamid.echo', origin: 'echo')
    described_class.new(message: outgoing).record(state: 'failed', error: 'Disconnected', confirmed_failure: true)
    expect(outgoing.reload.status).to eq('sent')
    expect(outgoing.content_attributes.dig('whatsapp_delivery', 'whatsapp_cloud')).to include('state' => 'sent', 'origin' => 'echo')
    expect(outgoing.content_attributes.dig('whatsapp_transport', 'fallback_pending')).not_to be(true)
  end

  it 'does not resend a historically delivered bubble that predates provider-scoped outcomes' do
    outgoing = message
    outgoing.update!(status: :delivered, source_id: 'synthetic-historical-id')
    clear_enqueued_jobs
    described_class.new(message: outgoing).record(state: 'failed', error: 'Late failure', confirmed_failure: true)
    expect(outgoing.reload).to have_attributes(status: 'delivered', source_id: 'synthetic-historical-id', external_error: nil)
    expect(outgoing.content_attributes.dig('whatsapp_delivery', 'unoapi', 'warning')).to eq('Late failure')
    expect(enqueued_jobs.none? { |job| job[:job] == SendReplyJob }).to be(true)
  end

  it 'leaves disabled links and messages from another account untouched and redacts diagnostic secrets' do
    outgoing = message
    described_class.new(message: outgoing).record(state: 'uncertain', error: 'Bearer syntheticsecret token=secret')
    expect(outgoing.reload.content_attributes.to_json).not_to include('syntheticsecret', 'token=secret')
    original = outgoing.attributes
    foreign_inbox = create(:channel_whatsapp, sync_templates: false, validate_provider_config: false).inbox
    expect(described_class.new(message: outgoing, inbox: foreign_inbox).record(state: 'failed', confirmed_failure: true)).to be(false)
    WhatsappInboxLink.for_inbox(uno.inbox).update!(enabled: false)
    expect(described_class.new(message: outgoing).record(state: 'failed', confirmed_failure: true)).to be(false)
    expect(outgoing.reload.attributes).to eq(original)
  end
end
