require 'rails_helper'

RSpec.describe Search::TextQuery, type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:contact) { create(:contact, :with_email, name: 'João Cláudia', account: account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  before { Current.account = account }
  after { Current.reset }

  ['joao', 'JOÃO', 'claudia', "Joa\u0303o"].each do |query|
    it "finds contacts through both APIs for #{query.inspect}" do
      get "/api/v1/accounts/#{account.id}/contacts/search", params: { q: query }, headers: user.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('payload').pluck('id')).to include(contact.id)
      search = SearchService.new(current_user: user, current_account: account, params: { q: query }, search_type: 'all').perform
      expect(search[:contacts].map(&:id)).to include(contact.id)
      expect(search[:conversations].map(&:id)).to include(conversation.id)
    end
  end

  [false, true].each do |gin|
    it "finds message content with accents (GIN=#{gin}) and preserves account isolation" do
      account.enable_features!('search_with_gin') if gin
      message = create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Manutenção de câmeras')
      other = create(:message, content: 'Manutenção de câmeras')
      search = SearchService.new(current_user: user, current_account: account, params: { q: 'manutencao de cameras' }, search_type: 'Message')
      expect(search.perform[:messages].map(&:id)).to include(message.id)
      expect(search.perform[:messages].map(&:id)).not_to include(other.id)
    end
  end

  it 'handles punctuation as text in GIN queries without a syntax error' do
    account.enable_features!('search_with_gin')
    message = create(:message, account: account, inbox: inbox, conversation: conversation, content: "João & Cláudia: d'água")
    search = SearchService.new(current_user: user, current_account: account,
                               params: { q: "joao & claudia: d'agua" }, search_type: 'Message')
    expect(search.perform[:messages].map(&:id)).to include(message.id)
  end

  it 'keeps wildcard characters literal and Unicode copies unchanged' do
    contact.update!(name: "Joa\u0303o 100%_suporte")
    expect(described_class.apply(account.contacts, %w[name], 'joao 100%_suporte')).to include(contact)
    expect(described_class.apply(account.contacts, %w[name], 'joao 100%_outro')).to be_empty
    expect(described_class.apply(account.contacts, %w[name], "' OR 1=1 --")).to be_empty
    expect(contact.reload.name).to eq("Joa\u0303o 100%_suporte")
  end

  it 'searches and ranks canned responses without accents' do
    response = create(:canned_response, account: account, short_code: 'saudação', content: 'Olá, João!')
    expect(described_class.apply(account.canned_responses, %w[short_code content], 'saudacao').order_by_search('saudacao')).to include(response)
    expect(described_class.apply(account.canned_responses, %w[short_code content], 'ola')).to include(response)
  end

  it 'preserves article prefix search, ranking and account scope' do
    portal = create(:portal, account: account)
    article = create(:article, account: account, portal: portal, author: user, title: 'Manutenção de câmeras', content: 'Olá, João!')
    expect(account.articles.text_search('manutencao cam')).to include(article)
    expect(account.articles.text_search('ola joao')).to include(article)
    expect(Article.where.not(account: account).text_search('manutencao cam')).not_to include(article)
  end
end
