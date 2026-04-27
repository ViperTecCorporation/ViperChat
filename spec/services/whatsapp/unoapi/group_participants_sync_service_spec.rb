require 'rails_helper'

describe Whatsapp::Unoapi::GroupParticipantsSyncService do
  subject(:service) { described_class.new(inbox: whatsapp_channel.inbox, conversation: conversation) }

  let(:whatsapp_channel) do
    create(
      :channel_whatsapp,
      provider: 'unoapi',
      provider_config: {
        'url' => 'https://uno.example.com',
        'api_key' => 'test_key',
        'business_account_id' => '556600000000'
      },
      sync_templates: false,
      validate_provider_config: false
    )
  end

  let(:group_contact) { create(:contact, account: whatsapp_channel.account, name: 'Equipe Comercial', email: '120363040468224422@g.us') }
  let(:group_contact_inbox) { create(:contact_inbox, inbox: whatsapp_channel.inbox, contact: group_contact, source_id: '120363040468224422@g.us') }
  let(:conversation) do
    create(
      :conversation,
      account: whatsapp_channel.account,
      inbox: whatsapp_channel.inbox,
      contact: group_contact,
      contact_inbox: group_contact_inbox,
      group: true,
      group_source_id: '120363040468224422@g.us',
      group_title: 'Equipe Comercial'
    )
  end

  let(:participants_url) { 'https://uno.example.com/v15.0/556600000000/groups/120363040468224422%40g.us/participants' }

  it 'hydrates group metadata and participants from Uno API' do
    stub_request(:get, participants_url).to_return(
      status: 200,
      body: {
        group: {
          subject: 'Equipe Comercial VIP',
          description: 'Canal comercial',
          invite_link: 'https://chat.whatsapp.com/test',
          picture: 'https://cdn.example.com/groups/group.jpg'
        },
        participants: [
          {
            jid: '556600000000@s.whatsapp.net',
            wa_id: '556600000000',
            name: 'Sessao',
            is_admin: true,
            role: 'admin'
          },
          {
            jid: '556699999999@s.whatsapp.net',
            wa_id: '556699999999',
            user_id: '123456789012345@lid',
            username: '@maria.vendas',
            name: 'Maria',
            picture: 'https://cdn.example.com/profile/maria.jpg',
            lid: '123456789012345@lid',
            is_admin: true,
            role: 'admin'
          }
        ]
      }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )

    expect(service.perform).to eq(:ok)

    conversation.reload
    expect(conversation.group_title).to eq('Equipe Comercial VIP')
    expect(conversation.group_description).to eq('Canal comercial')
    expect(conversation.group_invite_link).to eq('https://chat.whatsapp.com/test')
    expect(conversation.additional_attributes['group_picture']).to eq('https://cdn.example.com/groups/group.jpg')
    expect(conversation.group_contacts_synced_at).to be_present
    expect(conversation.group_session_admin).to be(true)
    maria_group_contact = conversation.group_contacts.joins(:contact).find_by!(contacts: { name: 'Maria' })
    expect(maria_group_contact.metadata).to include(
      'role' => 'admin',
      'is_admin' => true,
      'lid' => '123456789012345@lid',
      'user_id' => '123456789012345@lid',
      'username' => '@maria.vendas'
    )
    expect(maria_group_contact.contact.name).to eq('Maria')
    expect(maria_group_contact.contact.bsuid).to eq('123456789012345@lid')
    expect(maria_group_contact.contact.whatsapp_username).to eq('@maria.vendas')
  end

  it 'stores false when the connected session is not an admin in the group' do
    stub_request(:get, participants_url).to_return(
      status: 200,
      body: {
        participants: [
          {
            jid: '556600000000@s.whatsapp.net',
            wa_id: '556600000000',
            name: 'Sessao',
            is_admin: false,
            role: 'member'
          }
        ]
      }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )

    expect(service.perform).to eq(:ok)
    expect(conversation.reload.group_session_admin).to be(false)
  end

  it 'clears invalid legacy participant email before updating the contact' do
    participant_contact = create(:contact, account: whatsapp_channel.account, name: 'Contato legado')
    participant_contact.update_columns(email: '47017208377581') # rubocop:disable Rails/SkipsModelValidations
    create(:contact_inbox, inbox: whatsapp_channel.inbox, contact: participant_contact, source_id: '47017208377581@lid')

    stub_request(:get, participants_url).to_return(
      status: 200,
      body: {
        participants: [
          {
            jid: '47017208377581@lid',
            user_id: '47017208377581@lid',
            name: 'Contato legado atualizado',
            username: '@legado'
          }
        ]
      }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )

    expect(service.perform).to eq(:ok)

    participant_contact.reload
    expect(participant_contact.email).to be_nil
    expect(participant_contact.bsuid).to eq('47017208377581@lid')
    expect(participant_contact.whatsapp_username).to eq('@legado')
  end

  it 'returns cache_miss when Uno API does not have cached participants' do
    stub_request(:get, participants_url).to_return(status: 404, body: {}.to_json, headers: { 'Content-Type' => 'application/json' })

    expect(service.perform).to eq(:cache_miss)
    expect(conversation.reload.group_contacts_synced_at).to be_nil
  end
end
