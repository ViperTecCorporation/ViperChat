require 'rails_helper'

RSpec.describe Imap::GoogleHistoryService do
  let(:channel) { create(:channel_email, provider: 'google') }
  let(:service) { described_class.new(channel: channel) }
  let(:imap) { instance_double(Net::IMAP, responses: { 'UIDVALIDITY' => [123] }) }
  let(:mailbox) { instance_double(Imap::ImapMailbox, process: true) }
  let(:raw) { "From: sender@example.com\r\nTo: #{channel.email}\r\nMessage-ID: <history-test@example.com>\r\nSubject: Test\r\n\r\nHello" }

  before do
    Google::EmailHistory.start!(channel, '7d')
    allow(service).to receive(:imap_client).and_return(imap)
    allow(imap).to receive(:uid_search).and_return([1])
    allow(imap).to receive(:uid_fetch).and_return([Net::IMAP::FetchData.new(1, 'INTERNALDATE' => 1.minute.ago, 'BODY[]' => raw)])
    allow(Imap::ImapMailbox).to receive(:new).and_return(mailbox)
  end

  it 'uses date boundaries without unread filtering and processes one batch' do
    service.perform
    expect(imap).to have_received(:uid_search).with(['SINCE', Time.current.utc.strftime('%d-%b-%Y'), 'BEFORE', 1.day.from_now.utc.strftime('%d-%b-%Y')])
    expect(mailbox).to have_received(:process).once
    expect(channel.reload.provider_config.dig('email_history', 'processed')).to eq(1)
  end

  it 'limits work to fifty messages per poll and saves a UID cursor' do
    allow(imap).to receive(:uid_search).and_return((1..100).to_a)
    service.perform
    expect(imap).to have_received(:uid_fetch).exactly(50).times
    expect(channel.reload.provider_config.dig('email_history', 'uid')).to eq(50)
  end

  it 'skips already imported messages' do
    allow(service).to receive(:email_already_present?).with(channel, 'history-test@example.com').and_return(true)
    service.perform
    expect(mailbox).not_to have_received(:process)
  end

  it 'does not advance the cursor on processing failure' do
    allow(mailbox).to receive(:process).and_raise(StandardError, 'failure')
    service.perform
    expect(channel.reload.provider_config.dig('email_history', 'status')).to eq('failed')
    expect(channel.provider_config.dig('email_history', 'uid')).to eq(0)
  end

  it 'does nothing after cancellation' do
    Google::EmailHistory.update!(channel, channel.provider_config.dig('email_history', 'id'), 'status' => 'stopped')
    service.perform
    expect(imap).not_to have_received(:uid_search)
  end

  it 'does not import mail outside the exact snapshot bounds' do
    allow(imap).to receive(:uid_fetch).and_return([Net::IMAP::FetchData.new(1, 'INTERNALDATE' => 13.months.ago, 'BODY[]' => raw)])
    service.perform
    expect(mailbox).not_to have_received(:process)
  end
end
