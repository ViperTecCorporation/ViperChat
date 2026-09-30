require 'rails_helper'

RSpec.describe Google::GmailClient do
  let(:channel) do
    create(:channel_email, provider: 'google', imap_enabled: true,
                           provider_config: { gmail_transport: 'api', access_token: 'test-token', refresh_token: 'test-refresh',
                                              expires_on: 1.hour.from_now.to_s })
  end
  let(:client) { described_class.new(channel: channel) }
  let(:base_url) { Google::GmailClient::BASE_URL }
  let(:mail) do
    Mail.new(from: 'sender@example.com', to: 'recipient@example.com', subject: 'Gmail API test',
             message_id: 'gmail-api-test@example.com', body: 'Hello from Gmail API')
  end
  let(:raw_response) do
    { id: 'msg1', threadId: 'thread1', raw: Base64.urlsafe_encode64(mail.encoded), internalDate: (Time.current.to_f * 1000).to_i.to_s }
  end

  describe 'HTTP client' do
    it 'lists only the requested page and authenticates with the current token' do
      request = stub_request(:get, "#{base_url}/messages")
                .with(query: { q: 'in:inbox', maxResults: 50, pageToken: 'page2' }, headers: { 'Authorization' => 'Bearer test-token' })
                .to_return(body: { messages: [{ id: 'msg1' }] }.to_json)
      expect(client.list_messages(query: 'in:inbox', page_token: 'page2')['messages']).to eq([{ 'id' => 'msg1' }])
      expect(request).to have_been_requested.once
    end

    it 'raises a sanitized error on quota failure without claiming success' do
      stub_request(:post, "#{base_url}/messages/send").to_return(status: 429, body: 'private contents test-token')
      expect { client.send_message(mail.encoded) }.to raise_error(CustomExceptions::GmailError, 'Gmail API request failed (HTTP 429)')
    end

    it 'records authentication failures but not rate limiting as an authorization error' do
      allow(channel).to receive(:authorization_error!)
      stub_request(:get, "#{base_url}/messages/msg1").with(query: { format: 'raw' }).to_return(status: 401)
      expect { client.message('msg1') }.to raise_error(/HTTP 401/)
      expect(channel).to have_received(:authorization_error!).once
    end

    it 'uses the renewed token and preserves the existing refresh token and transport' do
      channel.update!(provider_config: channel.provider_config.merge('expires_on' => 1.hour.ago.to_s))
      stub_request(:post, 'https://oauth2.googleapis.com/token')
        .to_return(body: { access_token: 'renewed-token', expires_in: 3600, token_type: 'Bearer' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      request = stub_request(:get, "#{base_url}/messages/msg1")
                .with(query: { format: 'raw' }, headers: { 'Authorization' => 'Bearer renewed-token' })
                .to_return(body: raw_response.to_json)
      client.message('msg1')
      expect(request).to have_been_requested
      expect(channel.reload.provider_config).to include('refresh_token' => 'test-refresh', 'gmail_transport' => 'api')
    end
  end

  describe 'delivery adapter' do
    it 'sends a complete MIME message with attachments and all recipients without SMTP' do
      mail.cc = ['cc@example.com']
      mail.bcc = ['hidden@example.com']
      mail.in_reply_to = 'previous@example.com'
      mail.attachments['test.txt'] = 'attachment contents'
      sent_mail = nil
      request = stub_request(:post, "#{base_url}/messages/send").with do |req|
        sent_mail = Mail.read_from_string(Base64.urlsafe_decode64(JSON.parse(req.body).fetch('raw')))
        true
      end.to_return(body: { id: 'sent1', threadId: 'thread1' }.to_json)
      Google::GmailDelivery.new(channel_id: channel.id).deliver!(mail)
      expect(request).to have_been_requested.once
      expect(sent_mail.to).to eq(['recipient@example.com'])
      expect(sent_mail.cc).to eq(['cc@example.com'])
      expect(sent_mail.bcc).to eq(['hidden@example.com'])
      expect(sent_mail.in_reply_to).to eq('previous@example.com')
      expect(sent_mail.attachments.first.decoded).to eq('attachment contents')
    end

    it 'does not send through the API for legacy channels' do
      channel.update!(provider_config: channel.provider_config.except('gmail_transport'))
      expect { Google::GmailDelivery.new(channel_id: channel.id).deliver!(mail) }.to raise_error(/not enabled/)
    end
  end

  describe 'message ingestion' do
    before do
      stub_request(:get, "#{base_url}/messages/msg1").with(query: { format: 'raw' }).to_return { { body: raw_response.to_json } }
    end

    it 'creates one incoming message, keeps its body and deduplicates subsequent polls' do
      service = Google::GmailMessageService.new(channel: channel, client: client)
      channel.inbox
      expect { service.perform('msg1') }.to change { channel.inbox.messages.incoming.count }.by(1)
      expect(channel.inbox.messages.incoming.last.content).to include('Hello from Gmail API')
      expect(channel.inbox.messages.incoming.last.external_source_ids['gmail_thread_id']).to eq('thread1')
      expect { service.perform('msg1') }.not_to(change { channel.inbox.messages.count })
    end

    it 'preserves attachments through the existing mailbox processor' do
      mail.attachments['test.txt'] = 'incoming attachment'
      stub_request(:get, "#{base_url}/messages/msg1")
        .with(query: { format: 'raw' })
        .to_return(body: raw_response.merge(raw: Base64.urlsafe_encode64(mail.encoded)).to_json)
      Google::GmailMessageService.new(channel: channel, client: client).perform('msg1')
      expect(channel.inbox.messages.incoming.last.attachments.first.file.download).to eq('incoming attachment')
    end

    it 'does not recreate messages deleted locally' do
      tracker = instance_double(Imap::DeletedMessageTracker, deleted?: true)
      allow(Imap::DeletedMessageTracker).to receive(:new).and_return(tracker)
      expect(Imap::ImapMailbox).not_to receive(:new)
      Google::GmailMessageService.new(channel: channel, client: client).perform('msg1')
    end

    it 'skips a message deleted from Gmail between listing and fetching' do
      stub_request(:get, "#{base_url}/messages/msg1").with(query: { format: 'raw' }).to_return(status: 404)
      expect(Imap::ImapMailbox).not_to receive(:new)
      expect { Google::GmailMessageService.new(channel: channel, client: client).perform('msg1') }.not_to raise_error
    end
  end

  describe 'durable polling' do
    let(:service) { Google::GmailSyncService.new(channel: channel) }

    it 'persists pagination with fixed bounds and advances the watermark only after the last page' do
      stub_request(:get, "#{base_url}/messages")
        .with(query: hash_including('maxResults' => '50')).to_return(body: { nextPageToken: 'page2' }.to_json)
      service.perform
      state = channel.reload.provider_config['gmail_sync'].dup
      expect(state['page_token']).to eq('page2')
      stub_request(:get, "#{base_url}/messages").with(query: hash_including('pageToken' => 'page2')).to_return(body: '{}')
      travel 10.minutes do
        service.perform
      end
      expect(channel.reload.provider_config['gmail_sync']).to eq('since' => state['until'])
    end

    it 'does not skip failed messages or lose the scan bounds on retry' do
      stub_request(:get, "#{base_url}/messages")
        .with(query: hash_including('maxResults' => '50')).to_return(body: { messages: [{ id: 'msg1' }] }.to_json)
      stub_request(:get, "#{base_url}/messages/msg1").with(query: { format: 'raw' }).to_return(status: 503)
      expect { service.perform }.to raise_error(/HTTP 503/)
      state = channel.reload.provider_config['gmail_sync'].dup
      travel 10.minutes do
        expect { service.perform }.to raise_error(/HTTP 503/)
      end
      expect(channel.reload.provider_config['gmail_sync']).to eq(state)
    end
  end

  describe 'conversation reply integration' do
    let(:conversation) { create(:conversation, inbox: channel.inbox, account: channel.account) }
    let(:message) { create(:message, conversation: conversation, account: channel.account, message_type: :outgoing, content: 'API reply') }

    before do
      allow(Net::SMTP).to receive(:new).and_raise('SMTP must not be used for Gmail API')
    end

    it 'uses the API even with old SMTP settings, and records the outgoing source ID' do
      channel.update!(smtp_enabled: true, smtp_address: 'old-smtp.example.com')
      request = stub_request(:post, "#{base_url}/messages/send").to_return(body: { id: 'sent1', threadId: 'thread1' }.to_json)
      delivery = ConversationReplyMailer.with(account: channel.account).email_reply(message)
      expect(delivery.message.delivery_method).to be_a(Google::GmailDelivery)
      expect(Net::SMTP).not_to receive(:new)
      Email::SendOnEmailService.new(message: message).perform
      expect(request).to have_been_requested.once
      expect(message.reload.source_id).to include("messages/#{message.id}@")
      expect(message.status).not_to eq('failed')
    end

    it 'marks an API error as failed without pretending the message was sent' do
      stub_request(:post, "#{base_url}/messages/send").to_return(status: 403)
      Email::SendOnEmailService.new(message: message).perform
      expect(message.reload.status).to eq('failed')
      expect(message.external_error).to eq('Gmail API request failed (HTTP 403)')
      expect(message.source_id).to be_nil
    end
  end

  describe 'history import' do
    it 'completes an empty import through the API, without IMAP' do
      Google::EmailHistory.start!(channel, '7d')
      stub_request(:get, "#{base_url}/messages").with(query: hash_including('maxResults' => '50')).to_return(body: '{}')
      expect(Net::IMAP).not_to receive(:new)
      Google::GmailHistoryService.new(channel: channel).perform
      expect(channel.reload.provider_config.dig('email_history', 'status')).to eq('completed')
    end

    it 'does not fetch stopped imports' do
      Google::EmailHistory.start!(channel, 'none')
      expect(described_class).not_to receive(:new)
      Google::GmailHistoryService.new(channel: channel).perform
    end

    it 'does not advance an import when a message fails' do
      Google::EmailHistory.start!(channel, '7d')
      stub_request(:get, "#{base_url}/messages")
        .with(query: hash_including('maxResults' => '50')).to_return(body: { messages: [{ id: 'msg1' }], nextPageToken: 'page2' }.to_json)
      stub_request(:get, "#{base_url}/messages/msg1").with(query: { format: 'raw' }).to_return(status: 503)
      expect { Google::GmailHistoryService.new(channel: channel).perform }.to raise_error(CustomExceptions::GmailError)
      history = channel.reload.provider_config['email_history']
      expect(history['status']).to eq('failed')
      expect(history['processed']).to eq(0)
      expect(history['gmail_page_token']).to be_nil
    end
  end
end
