class Google::GmailClient
  SCOPES = %w[https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/gmail.send].freeze
  BASE_URL = 'https://gmail.googleapis.com/gmail/v1/users/me'.freeze

  pattr_initialize [:channel!]

  def list_messages(query:, page_token: nil)
    request(:get, '/messages', query: { q: query, maxResults: 50, pageToken: page_token }.compact)
  end

  def message(id)
    request(:get, "/messages/#{ERB::Util.url_encode(id)}", query: { format: 'raw' })
  end

  def send_message(raw, thread_id: nil)
    payload = { raw: Base64.urlsafe_encode64(raw, padding: false), threadId: thread_id }.compact
    request(:post, '/messages/send', body: payload.to_json)
  end

  def message_metadata(id)
    request(:get, "/messages/#{ERB::Util.url_encode(id)}", query: { format: 'metadata', metadataHeaders: ['Message-ID'] })
  end

  private

  def request(method, path, options)
    token = Google::RefreshOauthTokenService.new(channel: channel).access_token
    response = HTTParty.public_send(method, "#{BASE_URL}#{path}", **options,
                                   headers: { 'Authorization' => "Bearer #{token}", 'Content-Type' => 'application/json' }, timeout: 30)
    unless response.success?
      channel.authorization_error! if response.code == 401
      # Never include the response body: it can contain user data or credentials.
      raise CustomExceptions::GmailError, response.code
    end

    JSON.parse(response.body)
  end
end
