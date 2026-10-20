require 'rails_helper'

RSpec.describe 'Authorized contact 231 phone maintenance' do
  it 'previews then retires only the cancelled identity, preserving history and conflicting evidence' do
    account = create(:account, id: 1)
    contact = create(:contact, id: 231, account: account, phone_number: '+5566996803524', bsuid: '242309471989955@lid')
    channels = [1, 18, 19].map do |id|
      channel = create(:channel_whatsapp, account: account, provider: 'unoapi', sync_templates: false, validate_provider_config: false)
      channel.inbox.update!(id: id)
      channel
    end
    [[231, 1], [13_510, 18], [14_673, 19], [98_444, 18], [103_074, 1], [114_286, 19]].each do |id, inbox_id|
      create(:contact_inbox, id: id, inbox: Inbox.find(inbox_id), contact: contact,
                             source_id: id < 98_000 ? '5566996803524' : '242309471989955@lid')
    end
    meta = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: channels.first.phone_number,
                                     sync_templates: false, validate_provider_config: false)
    link = WhatsappInboxLink.create!(account: account, primary_inbox: Inbox.find(1), secondary_inbox: meta.inbox,
                                     default_provider: 'unoapi', enabled: true)
    identity = WhatsappMessageIdentity.create!(account: account, inbox: meta.inbox, channel: meta, provider: 'whatsapp_cloud',
                                               external_id: 'synthetic-event-486', provider_message_id: '3EB0110B8308CA4CD017DE',
                                               observations: { participants: { to: '556699367556' } })
    event = WhatsappUnifiedEvent.create!(id: 486, whatsapp_inbox_link: link, whatsapp_message_identity: identity,
                                         activation_cutoff: link.activated_at, state: 'review', reason: 'correlation_conflict',
                                         payload: { 'captured' => 'unchanged' })
    conversation = create(:conversation, account: account, inbox: Inbox.find(1), contact: contact, contact_inbox: ContactInbox.find(103_074))
    message = create(:message, account: account, inbox: Inbox.find(1), conversation: conversation)
    message.attachments.create!(account: account, file_type: :image,
                                file: { io: StringIO.new('history-media'), filename: 'history.png', content_type: 'image/png' })
    original = [contact.reload.attributes, conversation.reload.attributes, message.reload.attributes, identity.reload.attributes]
    script = Rails.root.join('script/validation/repair_contact_231_phone_change_20261020.rb')
    snapshot = { contact: contact.reload.attributes, aliases: contact.contact_inboxes.order(:id).map(&:attributes),
                 event: event.reload.attributes, identity: identity.reload.attributes }
    fingerprint = Digest::SHA256.hexdigest(snapshot.to_json)
    expect do
      load script
    rescue SystemExit
      nil
    end.to output(/"fingerprint": "#{fingerprint}"/).to_stdout
    expect(contact.reload.attributes).to eq(original.first)
    with_modified_env APPLY_CONTACT_231: 'yes', CONTACT_231_FINGERPRINT: fingerprint do
      expect { load script }.to output(/"preserved_counts": \[\s*1,\s*1,\s*1,\s*1,\s*1\s*\]/).to_stdout
    end
    expect(contact.reload).to have_attributes(id: 231, phone_number: '+5566996803524', bsuid: nil)
    expect([conversation.reload.attributes, message.reload.attributes, identity.reload.attributes]).to eq(original.drop(1))
    expect(event.reload).to have_attributes(state: 'disabled', reason: 'retired_recipient_after_phone_change', payload: { 'captured' => 'unchanged' })
    expect([contact.contact_inboxes.count, contact.contact_inboxes.active_whatsapp_identity.pluck(:source_id)])
      .to eq([6, ['5566996803524'] * 3])
  end
end
