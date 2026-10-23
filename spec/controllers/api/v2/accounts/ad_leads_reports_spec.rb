require 'rails_helper'

RSpec.describe 'Ad leads report', type: :request do
  let(:account) { create(:account, reporting_timezone: 'America/Cuiaba') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:path) { "/api/v2/accounts/#{account.id}/reports/partner_ad_leads" }

  it 'includes unpaired inboxes, identifies the contact and ignores posts and incomplete referrals' do
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    inbox = create(:inbox, account: account, channel: channel)
    contact = create(:contact, account: account, name: 'SYNTHETIC Ad Lead', phone_number: '+5511999999999')
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
    time = Time.iso8601('2026-10-20T10:00:00-04:00')
    message = create(:message, account: account, conversation: conversation, created_at: time,
                               content_attributes: { referral: { source_type: 'ad', source_id: 'synthetic-ad' } })
    create(:message, account: account, conversation: conversation, created_at: time + 1.minute, message_type: :outgoing,
                     status: :delivered, content_attributes: { whatsapp_transport: { provider: 'whatsapp_cloud' } })
    create(:message, account: account, conversation: conversation, created_at: time + 2.minutes,
                     content_attributes: { referral: { source_type: 'post', source_id: 'synthetic-post' } })
    create(:message, account: account, conversation: conversation, created_at: time + 3.minutes,
                     content_attributes: { referral: { source_type: 'ad' } })
    get path, headers: admin.create_new_auth_token, params: { from: '2026-10-01', to: '2026-10-23' }
    expect(response).to have_http_status(:ok)
    data = response.parsed_body
    expect(data['totals']).to include('ad_referrals' => 1, 'ad_contacts' => 1)
    expect(data.dig('simulation', 'ad_leads').first).to include('message_id' => message.id, 'contact_id' => contact.id,
                                                                'contact_name' => contact.name, 'ad_source_id' => 'synthetic-ad',
                                                                'window_days' => 7, 'free_meta_messages' => 1)
    expect(data['available_pairs']).to eq([])
  end

  it 'does not allow ordinary agents or users from another account' do
    agent = create(:user, account: account, role: :agent)
    get path, headers: agent.create_new_auth_token, params: { from: '2026-10-01', to: '2026-10-23' }
    expect(response).to have_http_status(:unauthorized)
    foreign = create(:user, account: create(:account), role: :administrator)
    get path, headers: foreign.create_new_auth_token, params: { from: '2026-10-01', to: '2026-10-23' }
    expect(response).not_to have_http_status(:ok)
  end
end
