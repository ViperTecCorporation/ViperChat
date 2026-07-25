require 'rails_helper'

describe Whatsapp::Unoapi::ContactSync::ContactImporter do
  subject(:importer) { described_class.new(channel: channel, payload: payload) }

  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      phone_number: '+5566996222471',
      provider: 'unoapi',
      sync_templates: false,
      validate_provider_config: false
    )
  end
  let(:payload) do
    {
      user_id: '273877414502425@lid',
      phone_number: '556698765432',
      display_name: 'Maria Silva',
      push_name: 'Maria',
      username: 'maria.silva',
      last_updated_ms: 1_784_977_424_000
    }
  end

  before do
    allow(Avatar::AvatarFromUrlJob).to receive(:enqueue_if_needed)
  end

  it 'creates one account contact with LID and normalized phone aliases in the inbox' do
    expect { importer.perform }.to change(account.contacts, :count).by(1)

    contact = account.contacts.find_by!(bsuid: '273877414502425@lid')
    expect(contact).to have_attributes(
      name: 'Maria Silva',
      phone_number: '+5566998765432',
      whatsapp_username: 'maria.silva'
    )
    expect(channel.inbox.contact_inboxes.where(contact: contact).pluck(:source_id))
      .to contain_exactly('273877414502425@lid', '5566998765432')
  end

  it 'reuses an account contact already linked to another inbox' do
    other_channel = create(
      :channel_whatsapp,
      account: account,
      phone_number: '+5566996333444',
      provider: 'unoapi',
      sync_templates: false,
      validate_provider_config: false
    )
    contact = create(:contact, account: account, phone_number: '+5566998765432', name: 'Nome mantido')
    create(:contact_inbox, inbox: other_channel.inbox, contact: contact, source_id: '5566998765432')

    expect { importer.perform }.not_to change(account.contacts, :count)

    expect(channel.inbox.contact_inboxes.where(contact: contact).pluck(:source_id))
      .to contain_exactly('273877414502425@lid', '5566998765432')
    expect(contact.reload.name).to eq('Nome mantido')
    expect(contact.bsuid).to eq('273877414502425@lid')
  end

  it 'replaces an invalid phone name but preserves a valid existing name' do
    invalid_contact = create(:contact, account: account, phone_number: '+5566998765432', name: '+55 (66) 99876-5432')

    importer.perform
    expect(invalid_contact.reload.name).to eq('Maria Silva')

    invalid_contact.update!(name: 'Nome escolhido pelo operador')
    described_class.new(
      channel: channel,
      payload: payload.merge(last_updated_ms: payload[:last_updated_ms] + 1, display_name: 'Nome da API')
    ).perform
    expect(invalid_contact.reload.name).to eq('Nome escolhido pelo operador')
  end

  it 'is idempotent when the same directory item is processed again' do
    importer.perform
    contact_count = account.contacts.count
    link_count = channel.inbox.contact_inboxes.count

    expect(importer.perform).to eq(:skipped)
    expect(account.contacts.count).to eq(contact_count)
    expect(channel.inbox.contact_inboxes.count).to eq(link_count)
  end

  it 'merges compatible pre-existing phone and LID contacts instead of treating the page as already imported' do
    phone_contact = create(:contact, account: account, phone_number: '+5566998765432', name: 'Maria Silva')
    lid_contact = create(:contact, account: account, bsuid: '273877414502425@lid', name: 'Maria')
    create(
      :contact_inbox,
      inbox: channel.inbox,
      contact: phone_contact,
      source_id: '5566998765432',
      additional_attributes: { 'unoapi_last_updated_ms' => payload[:last_updated_ms] }
    )
    create(
      :contact_inbox,
      inbox: channel.inbox,
      contact: lid_contact,
      source_id: '273877414502425@lid',
      additional_attributes: { 'unoapi_last_updated_ms' => payload[:last_updated_ms] }
    )

    expect { importer.perform }.to change(account.contacts, :count).by(-1)

    contact_ids = channel.inbox.contact_inboxes.where(source_id: ['5566998765432', '273877414502425@lid']).pluck(:contact_id)
    expect(contact_ids.uniq).to contain_exactly(phone_contact.id)
    expect(phone_contact.reload.bsuid).to eq('273877414502425@lid')
  end

  it 'does not merge a phone already associated with a different LID' do
    create(
      :contact,
      account: account,
      phone_number: '+5566998765432',
      bsuid: 'other-user@lid',
      name: 'Outra pessoa'
    )

    expect { importer.perform }.to raise_error(
      described_class::IdentityConflictError,
      /already belongs to LID/
    )
    expect(account.contacts.count).to eq(1)
  end
end
