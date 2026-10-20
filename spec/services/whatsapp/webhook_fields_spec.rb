require 'rails_helper'

describe Whatsapp::WebhookFields do
  it 'keeps optional and calling subscriptions opt-in' do
    expect(described_class::DEFAULT).to eq(%w[messages smb_message_echoes])
    expect(described_class::ALL).to include(*described_class::ADMIN, *described_class::GROUP, *described_class::MESSAGING, 'calls')
    expect(described_class::ALL.uniq).to eq(described_class::ALL)
    expect(described_class::ADMIN).to include('history', 'security', 'smb_app_state_sync', 'user_preferences')
  end
end
