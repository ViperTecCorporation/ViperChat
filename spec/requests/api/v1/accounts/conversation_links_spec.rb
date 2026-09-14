require 'rails_helper'

RSpec.describe 'Conversation links', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:conversation) { create(:conversation, account: account).reload }
  let(:url) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/links" }
  let(:headers) { user.create_new_auth_token }

  around do |example|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original
  end

  it 'requires authentication' do
    get url
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects an agent without conversation access' do
    agent = create(:user, account: account)
    get url, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'counts URLs, normalizes www and removes markdown closing punctuation' do
    create(:message, account: account, conversation: conversation,
                     content: '[Site](https://example.com/path) www.example.org. https://example.com/path')
    get url, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['total_count']).to eq(2)
    expect(response.parsed_body['payload'].pluck('url')).to contain_exactly('https://example.com/path', 'https://www.example.org')
  end

  it 'paginates the full history and excludes other conversations' do
    create(:message, account: account, conversation: conversation, content: (1..30).map { |n| "https://example.com/#{n}" }.join(' '))
    create(:message, account: account, content: 'https://other.example.com')
    get url, headers: headers
    expect(response.parsed_body['total_count']).to eq(30)
    expect(response.parsed_body['payload'].length).to eq(25)
    expect(response.parsed_body['has_more']).to be(true)
    get url, headers: headers, params: { page: 2 }
    expect(response.parsed_body['payload'].length).to eq(5)
    expect(response.parsed_body['has_more']).to be(false)
  end

  it 'lists recent messages first despite the association default order' do
    older = create(:message, account: account, conversation: conversation, content: 'https://example.com/older', created_at: 2.days.ago)
    recent = create(:message, account: account, conversation: conversation, content: 'https://example.com/recent', created_at: 1.day.ago)
    newest = create(:message, account: account, conversation: conversation, content: 'https://example.com/newest', created_at: recent.created_at)

    get url, headers: headers

    expect(response.parsed_body['payload'].pluck('message_id')).to eq([newest.id, recent.id, older.id])
  end

  it 'invalidates cached results after edits and deletion' do
    message = create(:message, account: account, conversation: conversation, content: 'https://example.com/old')
    get url, headers: headers
    message.update!(content: 'https://example.com/new')
    get url, headers: headers
    expect(response.parsed_body['payload'].pluck('url')).to eq(['https://example.com/new'])
    message.destroy!
    get url, headers: headers
    expect(response.parsed_body['total_count']).to eq(0)
  end

  it 'does not invalidate the cache for ordinary messages' do
    create(:message, account: account, conversation: conversation, content: 'https://example.com')
    get url, headers: headers
    revision = Rails.cache.read(Conversations::LinksService.revision_key(conversation.id))
    create(:message, account: account, conversation: conversation, content: 'Bom dia')
    expect(Rails.cache.read(Conversations::LinksService.revision_key(conversation.id))).to eq(revision)
    service = Conversations::LinksService.new(conversation)
    allow(Conversations::LinksService).to receive(:new).and_return(service)
    expect(service).not_to receive(:extract_links)
    get url, headers: headers
    expect(response.parsed_body['total_count']).to eq(1)
  end
end
