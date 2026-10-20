require 'rails_helper'

RSpec.describe 'WhatsApp contact phone changes', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'unoapi', sync_templates: false, validate_provider_config: false) }
  let(:contact) { create(:contact, account: account, phone_number: '+5566999367556', bsuid: '242309471989955@lid') }

  it 'retires the old routing identity through the real update API without rewriting source IDs' do
    old_alias = create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: '5566999367556')
    lid_alias = create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: '242309471989955@lid')
    conversation = create(:conversation, account: account, inbox: channel.inbox, contact: contact, contact_inbox: lid_alias)
    patch "/api/v1/accounts/#{account.id}/contacts/#{contact.id}", headers: admin.create_new_auth_token,
                                                                   params: { phone_number: '+5566996803524' }, as: :json
    expect(response).to have_http_status(:ok)
    expect(contact.reload).to have_attributes(phone_number: '+5566996803524', bsuid: nil)
    expect(old_alias.reload.source_id).to eq('5566999367556')
    expect(lid_alias.reload.source_id).to eq('242309471989955@lid')
    expect([old_alias, lid_alias]).to all(be_whatsapp_identity_retired)
    expect(conversation.reload.contact_inbox_id).to eq(lid_alias.id)
    expect(contact.contact_inboxes.active_whatsapp_identity.pluck(:source_id)).to eq(['5566996803524'])
  end
end
