require 'rails_helper'

RSpec.describe Google::EmailHistory do
  let(:channel) { create(:channel_email, provider: 'google', provider_config: { access_token: 'test' }) }

  it 'rejects arbitrary periods and all history' do
    [nil, 'all', '13m', '-1', '365', 365].each do |period|
      expect { described_class.start!(channel, period) }.to raise_error(ArgumentError)
    end
  end

  it 'limits the snapshot to twelve calendar months and preserves credentials' do
    travel_to Time.utc(2026, 9, 26, 12) do
      described_class.start!(channel, '12m', new_channel: true)
      config = channel.reload.provider_config
      expect(config['access_token']).to eq('test')
      expect(config['receive_since']).to eq(Time.current.iso8601)
      expect(config.dig('email_history', 'since')).to eq(Time.utc(2025, 9, 26, 12).iso8601)
      expect(config.dig('email_history', 'status')).to eq('running')
    end
  end

  it 'does not change live mail cutoff for an existing inbox' do
    described_class.start!(channel, '7d')
    expect(channel.reload.provider_config).not_to have_key('receive_since')
  end

  it 'does not queue historical mail for new-only selection' do
    described_class.start!(channel, 'none', new_channel: true)
    expect(channel.reload.provider_config.dig('email_history', 'status')).to eq('stopped')
  end

  it 'rejects stale progress after cancellation or restart' do
    described_class.start!(channel, '30d')
    id = channel.provider_config.dig('email_history', 'id')
    described_class.update!(channel, id, 'status' => 'stopped')
    expect(described_class.update!(channel, id, 'status' => 'completed')).to be false
    described_class.start!(channel, '3m')
    expect(described_class.update!(channel, id, 'uid' => 10)).to be false
  end
end
