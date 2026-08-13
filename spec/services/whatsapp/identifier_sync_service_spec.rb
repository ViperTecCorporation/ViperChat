require 'rails_helper'

describe Whatsapp::IdentifierSyncService do
  let(:channel) do
    create(:channel_whatsapp, provider: 'unoapi', sync_templates: false, validate_provider_config: false)
  end
  let(:contact) { create(:contact, account: channel.account, phone_number: '+5511912345678') }
  let(:phone_link) do
    create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: '5511912345678')
  end

  it 'normalizes a device suffix and replaces the old LID in the same inbox' do
    old_link = create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: '111111111111@lid')

    described_class.new(contact_inbox: phone_link, contact: contact).perform(
      source_ids: ['5511912345678', '222222222222:70@lid']
    )

    expect(channel.inbox.contact_inboxes.where(contact: contact).pluck(:source_id)).to contain_exactly(
      '5511912345678',
      '222222222222@lid'
    )
    expect(ContactInbox.exists?(old_link.id)).to be(true)
    expect(old_link.reload.source_id).to eq('222222222222@lid')
  end

  it 'does not replace a LID belonging to another inbox' do
    other_channel = create(:channel_whatsapp, provider: 'unoapi', sync_templates: false, validate_provider_config: false)
    create(:contact_inbox, inbox: other_channel.inbox, contact: contact, source_id: '111111111111@lid')

    described_class.new(contact_inbox: phone_link, contact: contact).perform(source_ids: ['222222222222@lid'])

    expect(other_channel.inbox.contact_inboxes.where(contact: contact).pluck(:source_id)).to eq(['111111111111@lid'])
    expect(channel.inbox.contact_inboxes.where(contact: contact).pluck(:source_id)).to include('222222222222@lid')
  end
end
