require 'rails_helper'

RSpec.describe Conversations::DirectRecipientService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'unoapi', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:recipient) { { phone_number: '66996222472' } }
  let(:service) { described_class.new(account: account, inbox: inbox, user: user, recipient: recipient) }

  it 'creates a minimal contact with a normalized phone as name' do
    result = service.perform
    expect(result.contact.phone_number).to eq('+5566996222472')
    expect(result.contact.name).to eq('+5566996222472')
    expect(result.source_id).to eq('5566996222472')
  end

  it 'reuses existing contacts and inbox links' do
    first = service.perform
    expect { service.perform }.not_to change(Contact, :count)
    expect(service.perform.id).to eq(first.id)
  end

  it 'resolves the contact by a BSUID alias without creating a duplicate' do
    contact = create(:contact, account: account, bsuid: '212721190613051@lid', name: 'Patricia')
    recipient.replace(bsuid: '212721190613051')
    expect(service.perform.contact_id).to eq(contact.id)
    expect(service.perform.source_id).to eq('212721190613051@lid')
  end

  it 'rejects numbers without an area code' do
    recipient[:phone_number] = '996222472'
    expect { service.perform }.to raise_error(ActionController::BadRequest)
  end

  it 'does not recreate a contact hidden from an agent' do
    agent = create(:user, account: account, role: :agent)
    create(:inbox_member, inbox: inbox, user: agent)
    account.enable_features!('hide_all_chats_for_agent')
    contact = create(:contact, account: account, phone_number: '+5566996222472')
    create(:conversation, account: account, inbox: inbox, contact: contact, assignee: user)
    restricted = described_class.new(account: account, inbox: inbox, user: agent, recipient: recipient)
    expect { restricted.perform }.to raise_error(Pundit::NotAuthorizedError)
    expect(account.contacts.where(phone_number: '+5566996222472').count).to eq(1)
  end
end
