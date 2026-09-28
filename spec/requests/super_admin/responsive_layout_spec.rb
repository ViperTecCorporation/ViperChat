require 'rails_helper'

RSpec.describe 'Superadmin responsive layout', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }

  before { sign_in(super_admin, scope: :super_admin) }

  it 'provides an accessible mobile menu and viewport on shared pages' do
    paths = ['/super_admin/accounts', "/super_admin/accounts/#{account.id}/edit",
             '/super_admin/settings', '/super_admin/app_config?config=general']
    paths.each do |path|
      get path
      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css('meta[name="viewport"]')['content']).to include('width=device-width')
      toggle = document.at_css('#super-admin-menu-toggle')
      expect(toggle['aria-controls']).to eq('super-admin-navigation')
      expect(toggle['aria-expanded']).to eq('false')
      expect(document.at_css('#super-admin-navigation')['class']).to include('hidden md:flex')
      expect(document.at_css('main')['class']).to include('min-w-0')
      expect(document.css('.translation_missing')).to be_empty
    end
  end

  it 'translates Rails form labels and submit actions in Portuguese' do
    get "/super_admin/accounts/#{account.id}/edit"
    document = Nokogiri::HTML(response.body)
    expect(document.at_css('label[for="account_name"]').text).to include('Nome')
    expect(document.at_css('label[for="account_locale"]').text).to include('Idioma')
    expect(document.at_css('input[type="submit"]')['value']).to eq('Salvar alterações')
  end

  it 'renders select values rather than internal Ruby objects on detail pages' do
    create(:account_user, account: account, user: super_admin, role: :agent)
    get "/super_admin/accounts/#{account.id}"
    document = Nokogiri::HTML(response.body)
    expect(document.at_css('#locale + .attribute-data').text.strip).to eq(account.locale)
    expect(document.text).not_to include('Administrate::Field::Select')
    expect(document.css('label').map { |label| label.text.strip }).to include('Usuário')
    expect(document.css('.cell-data--select').map { |cell| cell.text.strip }).to include('Agente')
  end
end
