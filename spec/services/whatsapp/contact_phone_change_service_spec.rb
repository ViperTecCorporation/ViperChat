require 'rails_helper'

RSpec.describe Whatsapp::ContactPhoneChangeService do
  let(:account) { create(:account) }
  let(:old_phone) { '+5566999367556' }
  let(:new_phone) { '+5566996803524' }
  let(:old_lid) { '242309471989955@lid' }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: '+5566996222471',
                              provider_config: { 'url' => 'https://uno.invalid', 'phone_number_id' => 'test-session', 'api_key' => 'synthetic' },
                              sync_templates: false, validate_provider_config: false)
  end
  let(:contact) { create(:contact, account: account, phone_number: old_phone, bsuid: old_lid, whatsapp_username: 'old_identity') }
  let!(:phone_alias) { create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: old_phone.delete_prefix('+')) }
  let!(:lid_alias) { create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: old_lid) }
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox, contact: contact, contact_inbox: lid_alias) }
  let(:message) { create(:message, account: account, inbox: channel.inbox, conversation: conversation, message_type: :outgoing) }

  it 'reproduces contact 231 without sending its old user_id with the new phone' do
    previous = [phone_alias, lid_alias].map { |row| row.attributes.slice('id', 'source_id', 'contact_id', 'inbox_id') }
    contact.update!(phone_number: new_phone)
    recipient = Whatsapp::OutboundRecipientService.new(conversation: conversation, inbox: channel.inbox).perform
    request_body = { to: recipient, user_id: old_lid, username: 'old_identity' }
    request_body['user_id'] = old_lid
    payload = Whatsapp::Unoapi::OutgoingIdentityPayload.new(request_body: request_body, message: message, inbox: channel.inbox).perform
    expect(payload).to eq(to: new_phone.delete_prefix('+'))
    expect(contact.reload.bsuid).to be_nil
    expect([phone_alias, lid_alias].map { |row| row.reload.attributes.slice('id', 'source_id', 'contact_id', 'inbox_id') }).to eq(previous)
    expect([phone_alias, lid_alias]).to all(be_whatsapp_identity_retired)
    expect(contact.additional_attributes['whatsapp_phone_changes'].last).to include('from' => old_phone, 'to' => new_phone, 'bsuid' => old_lid)
  end

  it 'keeps conversations, messages, attachment IDs and blobs intact' do
    file = { io: StringIO.new('synthetic-history-media'), filename: 'history.png', content_type: 'image/png' }
    attachment = message.attachments.create!(account: account, file_type: :image, file: file)
    original = [conversation.reload.attributes, message.reload.attributes, attachment.reload.attributes, attachment.file.blob.reload.attributes]
    counts = [Conversation.count, Message.count, Attachment.count, ActiveStorage::Blob.count]
    contact.update!(phone_number: new_phone)
    after_change = [conversation.reload.attributes, message.reload.attributes, attachment.reload.attributes, attachment.file.blob.reload.attributes]
    expect(after_change).to eq(original)
    expect([Conversation.count, Message.count, Attachment.count, ActiveStorage::Blob.count]).to eq(counts)
  end

  it 'preserves the LID when only the Brazilian ninth-digit representation changes' do
    contact.update_columns(phone_number: '+556699367556') # rubocop:disable Rails/SkipsModelValidations
    contact.reload.update!(phone_number: old_phone)
    expect(contact.reload.bsuid).to eq(old_lid)
    expect(lid_alias.reload).not_to be_whatsapp_identity_retired
    expect(Whatsapp::Unoapi::LidIdentity.for_message(message, inbox: channel.inbox)).to eq(old_lid)
  end

  it 'does not retire identities for a name edit or an initial phone enrichment' do
    contact.update!(name: 'Updated name')
    expect(lid_alias.reload).not_to be_whatsapp_identity_retired
    contact.update_columns(phone_number: nil) # rubocop:disable Rails/SkipsModelValidations
    contact.reload.update!(phone_number: old_phone)
    expect(contact.reload.bsuid).to eq(old_lid)
    expect(lid_alias.reload).not_to be_whatsapp_identity_retired
  end

  it 'does not retire anything if the new phone fails validation' do
    create(:contact, account: account, phone_number: new_phone)
    expect { contact.update!(phone_number: new_phone) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(lid_alias.reload).not_to be_whatsapp_identity_retired
    expect(contact.reload).to have_attributes(phone_number: old_phone, bsuid: old_lid)
  end

  it 'rolls back retirement when the new alias belongs to another contact' do
    other = create(:contact, account: account)
    create(:contact_inbox, inbox: channel.inbox, contact: other, source_id: new_phone.delete_prefix('+'))
    expect { contact.update!(phone_number: new_phone) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(lid_alias.reload).not_to be_whatsapp_identity_retired
    expect(contact.reload).to have_attributes(phone_number: old_phone, bsuid: old_lid)
  end

  it 'accepts a newly observed LID without deleting the retired alias or moving its history' do
    conversation
    contact.update!(phone_number: new_phone)
    current = contact.contact_inboxes.active_whatsapp_identity.find_by!(inbox: channel.inbox)
    Whatsapp::IdentifierSyncService.new(contact_inbox: current, contact: contact).perform(source_ids: ['998877665544332@lid'])
    expect(lid_alias.reload).to be_whatsapp_identity_retired
    expect(conversation.reload.contact_inbox_id).to eq(lid_alias.id)
    expect(Whatsapp::Unoapi::LidIdentity.for_message(message, inbox: channel.inbox)).to eq('998877665544332@lid')
  end

  it 'does not interpret the retired LID as evidence for the new phone' do
    identity = WhatsappMessageIdentity.create!(account: account, inbox: channel.inbox, channel: channel,
                                               provider: 'unoapi', external_id: 'synthetic-participant')
    contact.update!(phone_number: new_phone)
    service = Whatsapp::MessageIdentityParticipantService.new(identity: identity)
    expect(service.equivalent?([old_lid], expected: new_phone)).to be(false)
  end

  it 'keeps a late old identity from overwriting the new identity during synchronization' do
    contact.update!(phone_number: new_phone)
    current = contact.contact_inboxes.active_whatsapp_identity.find_by!(inbox: channel.inbox)
    service = Whatsapp::IdentifierSyncService.new(contact_inbox: current, contact: contact)
    service.perform(source_ids: ['998877665544332@lid'])
    service.perform(source_ids: [old_lid], username: 'old_identity')
    expect(Whatsapp::Unoapi::LidIdentity.for_message(message, inbox: channel.inbox)).to eq('998877665544332@lid')
    expect(lid_alias.reload).to be_whatsapp_identity_retired
  end

  it 'learns the new user_id from a webhook while keeping the old contact and all historical aliases' do
    conversation
    contact.update!(phone_number: new_phone)
    result = ContactInboxWithContactBuilder.new(inbox: channel.inbox, source_id: new_phone.delete_prefix('+'),
                                                contact_attributes: { phone_number: new_phone, bsuid: '998877665544332@lid' }).perform
    expect(result.contact_id).to eq(contact.id)
    expect(contact.reload.bsuid).to eq('998877665544332@lid')
    ContactInboxWithContactBuilder.new(inbox: channel.inbox, source_id: old_lid,
                                       contact_attributes: { phone_number: old_phone, bsuid: old_lid }).perform
    expect(contact.reload).to have_attributes(phone_number: new_phone, bsuid: '998877665544332@lid')
    expect(conversation.reload.contact_inbox_id).to eq(lid_alias.id)
    expect(lid_alias.reload).to be_whatsapp_identity_retired
  end

  it 'does not restore the old identity from an old directory page' do
    contact.update!(phone_number: new_phone)
    importer = Whatsapp::Unoapi::ContactSync::ContactImporter.new(channel: channel,
                                                                  payload: { user_id: old_lid, phone_number: old_phone })
    expect { importer.perform }.to raise_error(Whatsapp::Unoapi::ContactSync::ContactImporter::IdentityConflictError)
    expect(contact.reload).to have_attributes(phone_number: new_phone, bsuid: nil)
  end

  it 'does not send the retired user_id in the provider HTTP request for a new message' do
    message
    contact.update!(phone_number: new_phone)
    request = stub_request(:post, %r{https://uno.invalid/.*/messages}).with do |http|
      body = JSON.parse(http.body)
      body['to'] == new_phone.delete_prefix('+') && body.exclude?('user_id') && body.exclude?('username')
    end.to_return(status: 200, body: { messages: [{ id: 'synthetic-new-message' }] }.to_json,
                  headers: { 'Content-Type' => 'application/json' })
    original_id = message.source_id
    service = Whatsapp::Providers::UnoapiService.new(whatsapp_channel: channel)
    expect(service.send_message(new_phone.delete_prefix('+'), message)).to eq('synthetic-new-message')
    expect(request).to have_been_requested.once
    expect(message.reload.source_id).to eq(original_id)
  end

  it 'retires aliases across the contact inboxes without changing the same LID in another account' do
    other_channel = create(:channel_whatsapp, account: account, provider: 'unoapi', sync_templates: false, validate_provider_config: false)
    other_alias = create(:contact_inbox, inbox: other_channel.inbox, contact: contact, source_id: old_lid)
    foreign = create(:contact, phone_number: old_phone, bsuid: old_lid)
    contact.update!(phone_number: new_phone)
    expect([lid_alias.reload, other_alias.reload]).to all(be_whatsapp_identity_retired)
    expect(contact.contact_inboxes.active_whatsapp_identity.order(:inbox_id).pluck(:source_id)).to eq([new_phone.delete_prefix('+')] * 2)
    expect(foreign.reload).to have_attributes(phone_number: old_phone, bsuid: old_lid)
  end

  it 'does not retire an alias already observed for the new phone' do
    known = create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: new_phone.delete_prefix('+'))
    contact.update!(phone_number: new_phone)
    expect(known.reload).not_to be_whatsapp_identity_retired
    expect(contact.contact_inboxes.active_whatsapp_identity.ids).to eq([known.id])
  end

  it 'does not allow a stale directory verification to restore the previous identity' do
    contact.update!(phone_number: new_phone)
    client = instance_double(Whatsapp::Unoapi::ContactSync::Client)
    allow(client).to receive(:verify_contact).with(new_phone.delete_prefix('+')).and_return(
      'status' => 'valid', 'wa_id' => '556699367556', 'user_id' => old_lid
    )
    expect(client).not_to receive(:import_contact)
    result = Whatsapp::Unoapi::ContactSync::ContactExporter.new(channel: channel, contact: contact, client: client).perform
    expect(result).to eq(:failed)
    expect(contact.reload).to have_attributes(phone_number: new_phone, bsuid: nil)
    expect(lid_alias.reload).to be_whatsapp_identity_retired
  end

  it 'selects the current recipient even when an unlinked conversation still points at its historical alias' do
    message
    contact.update!(phone_number: new_phone)
    service = Whatsapp::SendOnWhatsappService.new(message: message)
    expect(service.send(:whatsapp_recipient)).to eq(new_phone.delete_prefix('+'))
    expect(conversation.reload.contact_inbox_id).to eq(lid_alias.id)
  end

  it 'does not force event-486 to match divergent recipients or rewrite its evidence' do
    meta = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+556696222471',
                                     sync_templates: false, validate_provider_config: false)
    link = WhatsappInboxLink.create!(account: account, primary_inbox: channel.inbox, secondary_inbox: meta.inbox,
                                     default_provider: 'unoapi', enabled: true)
    common = { 'direction' => 'outgoing', 'kind' => 'text', 'contract_version' => 1 }
    original = '3EB0110B8308CA4CD017DE'
    uno_identity = WhatsappMessageIdentity.create!(account: account, inbox: channel.inbox, channel: channel, provider: 'unoapi',
                                                   external_id: 'synthetic-event-486-uno', provider_message_id: original,
                                                   observations: common.merge('business_number' => channel.phone_number,
                                                                              'participants' => { 'from' => channel.phone_number,
                                                                                                  'to' => new_phone.delete_prefix('+') }))
    meta_identity = WhatsappMessageIdentity.create!(account: account, inbox: meta.inbox, channel: meta, provider: 'whatsapp_cloud',
                                                    external_id: 'wamid.HBgTQlIuMTA4OTY5OTI0MzkxMTI0MBUUABEYFjNFQjAxMTBCODMwOENBNENEMDE3REUA',
                                                    provider_message_id: original,
                                                    observations: common.merge('business_number' => meta.phone_number,
                                                                               'participants' => { 'from' => meta.phone_number,
                                                                                                   'to' => '556699367556',
                                                                                                   'to_user_id' => 'BR.1089699243911240' }))
    event = Whatsapp::UnifiedEventService.defer(link: link, identity: meta_identity,
                                                value: { message_echoes: [{ to: '556699367556', to_user_id: 'BR.1089699243911240' }] },
                                                reason: 'correlation_conflict')
    evidence = [uno_identity.reload.attributes, meta_identity.reload.attributes, event.reload.attributes]
    contact.update!(phone_number: new_phone)
    comparison = Whatsapp::MessageIdentityCorrelationService.new(identity: meta_identity, partner_inbox: channel.inbox).perform
    expect(comparison[:status]).to eq('incompatible')
    expect(Whatsapp::UnifiedEventResolutionService.new(event: event).perform).to be(false)
    expect([uno_identity.reload.attributes, meta_identity.reload.attributes, event.reload.attributes]).to eq(evidence)
    expect(event.state).to eq('review')
  end
end
