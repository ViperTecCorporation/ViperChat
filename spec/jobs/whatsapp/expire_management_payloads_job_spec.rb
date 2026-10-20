require 'rails_helper'

RSpec.describe Whatsapp::ExpireManagementPayloadsJob do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }

  it 'clears expired raw bodies but retains receipt IDs, digest and summaries' do
    event = WhatsappManagementEvent.create!(account: channel.account, channel: channel, inbox: channel.inbox, field: 'history',
                                            digest: 'a' * 64, state: 'pending_import', reason: 'user_choice_required',
                                            payload: { history: [] }, details: { 'messages_count' => 10 }, expires_at: 1.minute.ago)
    id = event.id
    2.times { described_class.perform_now }
    expect(event.reload).to have_attributes(id: id, digest: 'a' * 64, payload: {}, details: { 'messages_count' => 10 },
                                           state: 'review', reason: 'payload_expired')
    expect(WhatsappManagementEvent.count).to eq(1)
    expect(channel.account.messages).to be_empty
  end
end
