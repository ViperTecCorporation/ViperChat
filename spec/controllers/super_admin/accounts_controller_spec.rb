require 'rails_helper'

RSpec.describe 'Super Admin accounts API', type: :request do
  include ActiveJob::TestHelper

  let!(:super_admin) { create(:super_admin) }
  let!(:account) { create(:account) }

  describe 'GET /super_admin/accounts' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get '/super_admin/accounts'
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated user' do
      it 'shows the list of accounts' do
        sign_in(super_admin, scope: :super_admin)
        get '/super_admin/accounts'
        expect(response).to have_http_status(:success)
        expect(response.body).to include('Novo conta')
        expect(response.body).to include(account.name)
      end
    end
  end

  describe 'POST /super_admin/accounts' do
    context 'when it is an authenticated user' do
      it 'creates an account while ignoring blank limits' do
        sign_in(super_admin, scope: :super_admin)

        expect do
          post '/super_admin/accounts', params: {
            account: {
              name: 'CIRI',
              locale: 'pt_BR',
              status: 'active',
              limits: {
                agents: '',
                inboxes: '10',
                captain_responses: '',
                captain_documents: '',
                emails: ''
              }
            }
          }
        end.to change(Account, :count).by(1)

        expect(response).to redirect_to("http://www.example.com/super_admin/accounts/#{Account.last.id}")
        expect(Account.last.limits).to eq('inboxes' => 10)
      end
    end
  end

  describe 'POST /super_admin/accounts/{account_id}/reset_cache' do
    before do
      create(:label, account: account)
      create(:inbox, account: account)
      create(:team, account: account)
    end

    after do
      Conversations::UnreadCounts::Store.clear_account!(account.id)
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/super_admin/accounts/#{account.id}/reset_cache"
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated user' do
      it 'shows the list of accounts' do
        expect(account.cache_keys.keys).to contain_exactly(:inbox, :label, :team)
        sign_in(super_admin, scope: :super_admin)

        now_timestamp = Time.now.utc.to_i
        post "/super_admin/accounts/#{account.id}/reset_cache"
        expect(response).to have_http_status(:redirect)
        expect(flash[:notice]).to eq('Cache keys cleared')

        range = now_timestamp..(now_timestamp + 10)
        expect(account.reload.cache_keys.values.all? { |v| range.cover?(v.to_i) }).to be(true)
      end

      it 'clears conversation unread count cache' do
        inbox = account.inboxes.first
        store = Conversations::UnreadCounts::Store
        inbox_key = store.inbox_key(account.id, inbox.id)
        store.mark_base_ready!(account.id)
        store.add_base_membership(account_id: account.id, inbox_id: inbox.id, label_ids: [], conversation_id: 1)

        sign_in(super_admin, scope: :super_admin)
        post "/super_admin/accounts/#{account.id}/reset_cache"

        expect(response).to have_http_status(:redirect)
        expect(store.base_ready?(account.id)).to be(false)
        expect(store.counts_for_keys([inbox_key])).to eq(inbox_key => 0)
      end
    end
  end

  describe 'DELETE /super_admin/accounts/{account_id}' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/super_admin/accounts/#{account.id}"
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated user' do
      it 'Deletes the account' do
        inbox = create(:inbox, account: account)
        group_contact = create(:contact, account: account, email: '120363040468224422@g.us')
        participant = create(:contact, account: account)
        contact_inbox = create(:contact_inbox, inbox: inbox, contact: group_contact, source_id: '120363040468224422@g.us')
        conversation = create(
          :conversation,
          account: account,
          inbox: inbox,
          contact: group_contact,
          contact_inbox: contact_inbox,
          group: true,
          group_source_id: '120363040468224422@g.us'
        )
        create(:group_contact, account: account, conversation: conversation, contact: participant)

        total_accounts = Account.count
        sign_in(super_admin, scope: :super_admin)

        perform_enqueued_jobs(only: DeleteObjectJob) do
          delete "/super_admin/accounts/#{account.id}"
        end

        expect(Account.count).to eq(total_accounts - 1)
      end
    end
  end
end
