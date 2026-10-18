require 'rails_helper'

RSpec.describe 'Operational WhatsApp inbox metadata', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:meta_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+556696222471',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:uno_channel) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: '+5566996222471',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:contact) { create(:contact, account: account, phone_number: '+5566996269251') }

  %w[whatsapp_cloud unoapi].each do |principal|
    context "with #{principal} principal" do
      let(:primary) { principal == 'whatsapp_cloud' ? meta_channel.inbox : uno_channel.inbox }
      let(:secondary) { principal == 'whatsapp_cloud' ? uno_channel.inbox : meta_channel.inbox }
      let!(:link) do
        WhatsappInboxLink.create!(account: account, primary_inbox: primary, secondary_inbox: secondary,
                                  default_provider: 'unoapi', enabled: true)
      end
      let!(:primary_alias) { create(:contact_inbox, inbox: primary, contact: contact, source_id: '556696269251') }
      let!(:secondary_alias) { create(:contact_inbox, inbox: secondary, contact: contact, source_id: '5566996269251') }

      it 'keeps both physical inboxes in the admin collection and adds operational metadata' do
        get "/api/v1/accounts/#{account.id}/inboxes", headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        inboxes = response.parsed_body.fetch('payload')
        expect(inboxes.pluck('id')).to include(primary.id, secondary.id)
        metadata = inboxes.find { |inbox| inbox['id'] == primary.id }.fetch('whatsapp_inbox_link')
        expect(metadata).to include('link_id' => link.id, 'primary_inbox_id' => primary.id,
                                    'primary_inbox_name' => primary.name, 'secondary_inbox_id' => secondary.id,
                                    'default_provider' => 'unoapi')
        expect(metadata.fetch('transports').pluck('provider')).to match_array(%w[unoapi whatsapp_cloud])
        metadata.fetch('transports').each do |transport|
          channel = transport.fetch('provider') == 'unoapi' ? uno_channel : meta_channel
          expect(transport).to include('inbox_id' => channel.inbox.id, 'channel_type' => 'Channel::Whatsapp',
                                       'message_templates' => channel.message_templates)
          expect(transport.fetch('label')).to eq(channel.provider == 'unoapi' ? 'ViperConnect' : 'Meta')
          expect(transport.keys).not_to include('provider_config', 'api_key', 'access_token')
        end
      end

      it 'exposes both transports to a primary-only agent without exposing physical secondary access' do
        create(:inbox_member, inbox: primary, user: agent)
        get "/api/v1/accounts/#{account.id}/inboxes", headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        inboxes = response.parsed_body.fetch('payload')
        expect(inboxes.pluck('id')).to include(primary.id)
        expect(inboxes.pluck('id')).not_to include(secondary.id)
        expect(inboxes.find { |inbox| inbox['id'] == primary.id }.fetch('whatsapp_inbox_link').fetch('transports').pluck('provider'))
          .to match_array(%w[unoapi whatsapp_cloud])
      end

      it 'does not expose operational metadata to a secondary-only agent' do
        create(:inbox_member, inbox: secondary, user: agent)
        get "/api/v1/accounts/#{account.id}/inboxes", headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        inboxes = response.parsed_body.fetch('payload')
        expect(inboxes.pluck('id')).to include(secondary.id)
        expect(inboxes.pluck('id')).not_to include(primary.id)
        expect(inboxes.find { |inbox| inbox['id'] == secondary.id }['whatsapp_inbox_link']).to be_nil
      end

      it 'adds safe metadata to slim inboxes in the contacts collection' do
        get "/api/v1/accounts/#{account.id}/contacts", headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        result = response.parsed_body.fetch('payload').find { |row| row['id'] == contact.id }
        expect(result.fetch('contact_inboxes').pluck('source_id')).to include(primary_alias.source_id, secondary_alias.source_id)
        slim = result.fetch('contact_inboxes').find { |row| row.dig('inbox', 'id') == primary.id }.fetch('inbox')
        expect(slim.fetch('whatsapp_inbox_link')).to include('link_id' => link.id, 'primary_inbox_id' => primary.id)
        expect(slim.fetch('whatsapp_inbox_link').fetch('transports').pluck('provider')).to match_array(%w[unoapi whatsapp_cloud])
        expect(slim.keys).not_to include('provider_config', 'api_key', 'access_token')
      end

      it 'does not leak principal metadata through contact aliases to a secondary-only agent' do
        account.disable_features!('hide_contacts_for_agent')
        create(:inbox_member, inbox: secondary, user: agent)
        get "/api/v1/accounts/#{account.id}/contacts", headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        result = response.parsed_body.fetch('payload').find { |row| row['id'] == contact.id }
        expect(result).to be_present
        result.fetch('contact_inboxes').each do |row|
          expect(row.fetch('inbox')['whatsapp_inbox_link']).to be_nil
        end
      end

      it 'uses the principal source alias in contactable compose choices' do
        get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/contactable_inboxes",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        choices = response.parsed_body.fetch('payload')
        expect(choices.pluck('inbox').pluck('id')).to eq([primary.id])
        expect(choices.sole.fetch('source_id')).to eq(primary_alias.source_id)
        expect(choices.sole.fetch('inbox').fetch('whatsapp_inbox_link')).to include('link_id' => link.id)
      end

      it 'omits metadata for a disabled pair without deleting either physical inbox' do
        link.update!(enabled: false)
        get "/api/v1/accounts/#{account.id}/inboxes", headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        inboxes = response.parsed_body.fetch('payload')
        expect(inboxes.pluck('id')).to include(primary.id, secondary.id)
        inboxes.each { |inbox| expect(inbox['whatsapp_inbox_link']).to be_nil }
      end
    end
  end

  it 'does not allow foreign-account access to the physical inbox collection' do
    outsider = create(:user, account: create(:account), role: :administrator)
    get "/api/v1/accounts/#{account.id}/inboxes", headers: outsider.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
