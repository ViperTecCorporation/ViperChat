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

  it 'collapses an existing mobile alias without the ninth digit even with the same update timestamp' do # rubocop:disable RSpec/ExampleLength
    channel.inbox.update!(lock_to_single_conversation: true)
    mobile_lid = '117398703231205@lid'
    mobile_payload = payload.merge(
      user_id: mobile_lid,
      phone_number: '551733453633',
      display_name: 'Celular com prefixo de fixo'
    )
    mobile_importer = described_class.new(channel: channel, payload: mobile_payload)
    contact = create(
      :contact,
      account: account,
      phone_number: '+551733453633',
      bsuid: mobile_lid,
      name: 'Celular com prefixo de fixo'
    )
    legacy_link = create(
      :contact_inbox,
      inbox: channel.inbox,
      contact: contact,
      source_id: '551733453633',
      additional_attributes: { 'unoapi_last_updated_ms' => payload[:last_updated_ms] }
    )
    canonical_link = create(
      :contact_inbox,
      inbox: channel.inbox,
      contact: contact,
      source_id: '5517933453633',
      additional_attributes: { 'unoapi_last_updated_ms' => payload[:last_updated_ms] }
    )
    lid_link = create(
      :contact_inbox,
      inbox: channel.inbox,
      contact: contact,
      source_id: mobile_lid,
      additional_attributes: { 'unoapi_last_updated_ms' => payload[:last_updated_ms] }
    )
    canonical_conversation = create(
      :conversation,
      account: account,
      inbox: channel.inbox,
      contact: contact,
      contact_inbox: canonical_link,
      last_activity_at: 2.days.ago
    )
    legacy_conversation = create(
      :conversation,
      account: account,
      inbox: channel.inbox,
      contact: contact,
      contact_inbox: legacy_link,
      last_activity_at: 1.day.ago
    )
    message = create(:message, account: account, inbox: channel.inbox, conversation: legacy_conversation, sender: contact)

    expect(mobile_importer.perform).to eq(:processed)
    expect(contact.reload.phone_number).to eq('+5517933453633')
    expect(channel.inbox.contact_inboxes.where(contact: contact).pluck(:source_id))
      .to contain_exactly('5517933453633', mobile_lid)
    expect(channel.inbox.conversations.where(contact: contact).count).to eq(1)
    expect(message.reload.conversation).to eq(legacy_conversation)
    expect(Conversation.exists?(canonical_conversation.id)).to be(false)
    expect(lid_link.reload.additional_attributes['unoapi_last_updated_ms']).to eq(payload[:last_updated_ms])
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

  it 'replaces WhatsApp technical identifiers used as contact names' do
    importer.perform
    contact = account.contacts.find_by!(bsuid: payload[:user_id])
    technical_names = [
      payload[:user_id],
      '5566998765432@s.whatsapp.net',
      '120363123456789@g.us',
      'status@broadcast',
      '123456789@newsletter'
    ]

    technical_names.each do |technical_name|
      contact.update!(name: technical_name)

      expect(importer.perform).to eq(:processed)
      expect(contact.reload.name).to eq('Maria Silva')
    end
  end

  it 'replaces a normalized JID without a suffix used as the contact name' do
    normalized_jid = '5566999424178'
    contact = create(
      :contact,
      account: account,
      phone_number: "+#{normalized_jid}",
      bsuid: normalized_jid,
      name: normalized_jid
    )

    result = described_class.new(
      channel: channel,
      payload: payload.merge(user_id: normalized_jid, phone_number: normalized_jid)
    ).perform

    expect(result).to eq(:processed)
    expect(contact.reload.name).to eq('Maria Silva')
  end

  it 'repairs a technical name when UnoAPI returns the same last_updated_ms' do
    importer.perform
    contact = account.contacts.find_by!(bsuid: payload[:user_id])
    contact.update!(name: payload[:user_id])

    expect(importer.perform).to eq(:processed)
    expect(contact.reload.name).to eq('Maria Silva')
  end

  it 'clears an invalid legacy email before updating the contact' do
    contact = create(:contact, account: account, phone_number: '+5566998765432', name: 'Maria Silva')
    contact.update_column(:email, '273877414502425') # rubocop:disable Rails/SkipsModelValidations

    expect(importer.perform).to eq(:processed)
    expect(contact.reload.email).to be_nil
  end

  it 'uses the normalized phone as the name when UnoAPI has no valid name' do
    phone_payload = payload.merge(display_name: nil, push_name: nil)
    phone_importer = described_class.new(channel: channel, payload: phone_payload)

    expect(phone_importer.perform).to eq(:processed)

    contact = account.contacts.find_by!(bsuid: payload[:user_id])
    expect(contact).to have_attributes(name: '+5566998765432', phone_number: '+5566998765432')
    expect(phone_importer.perform).to eq(:skipped)
  end

  it 'repairs a fixed line previously stored with an incorrect ninth digit' do
    fixed_lid = '162332634288180@lid'
    contact = create(
      :contact,
      account: account,
      phone_number: '+5566935175000',
      bsuid: fixed_lid,
      name: '+5566935175000'
    )
    contact_inbox = create(
      :contact_inbox,
      inbox: channel.inbox,
      contact: contact,
      source_id: '5566935175000'
    )
    fixed_importer = described_class.new(
      channel: channel,
      payload: payload.merge(user_id: fixed_lid, phone_number: '556635175000', display_name: nil, push_name: nil)
    )

    expect(fixed_importer.perform).to eq(:processed)
    expect(contact.reload).to have_attributes(name: '+556635175000', phone_number: '+556635175000')
    expect(contact_inbox.reload.source_id).to eq('556635175000')
  end

  it 'merges duplicate fixed-line contacts when one has an incorrect ninth digit' do
    fixed_lid = '162332634288180@lid'
    stale_contact = create(
      :contact,
      account: account,
      phone_number: '+5566935175000',
      bsuid: fixed_lid,
      name: '+5566935175000'
    )
    create(:contact_inbox, inbox: channel.inbox, contact: stale_contact, source_id: fixed_lid)
    correct_contact = create(:contact, account: account, phone_number: '+556635175000', name: 'Telefone fixo')
    fixed_importer = described_class.new(
      channel: channel,
      payload: payload.merge(user_id: fixed_lid, phone_number: '556635175000', display_name: 'Telefone fixo')
    )

    expect { fixed_importer.perform }.to change(account.contacts, :count).by(-1)
    expect(correct_contact.reload).to have_attributes(phone_number: '+556635175000', bsuid: fixed_lid)
    expect(channel.inbox.contact_inboxes.where(source_id: fixed_lid).pick(:contact_id)).to eq(correct_contact.id)
  end

  it 'preserves a valid Brazilian toll-free number and uses it as the fallback name' do
    toll_free_lid = '110329170280512@lid'
    toll_free_importer = described_class.new(
      channel: channel,
      payload: payload.merge(user_id: toll_free_lid, phone_number: '558007440010', display_name: nil, push_name: nil)
    )

    expect(toll_free_importer.perform).to eq(:processed)

    contact = account.contacts.find_by!(bsuid: toll_free_lid)
    expect(contact).to have_attributes(name: '+558007440010', phone_number: '+558007440010')
  end

  it 'is idempotent when the same directory item is processed again' do
    importer.perform
    contact_count = account.contacts.count
    link_count = channel.inbox.contact_inboxes.count

    expect(importer.perform).to eq(:skipped)
    expect(account.contacts.count).to eq(contact_count)
    expect(channel.inbox.contact_inboxes.count).to eq(link_count)
  end

  it 'keeps idempotency when page identities are preloaded in batches' do
    importer.perform
    page_importer = described_class.build_for_page(channel: channel, payloads: [payload]).first

    expect(page_importer.perform).to eq(:skipped)
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

  it 'replaces a stale LID after the WhatsApp network validates the canonical LID' do
    stale_lid = '99226763698235@lid'
    contact = create(
      :contact,
      account: account,
      phone_number: '+5566998765432',
      bsuid: stale_lid,
      name: 'Maria Silva'
    )
    create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: '5566998765432')
    create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: stale_lid)
    client = instance_double(
      Whatsapp::Unoapi::ContactSync::Client,
      verify_contact: {
        'input' => '556698765432',
        'wa_id' => '556698765432',
        'user_id' => payload[:user_id],
        'status' => 'valid'
      }
    )
    verified_importer = described_class.new(channel: channel, payload: payload, client: client)

    expect(verified_importer.perform).to eq(:processed)
    expect(client).to have_received(:verify_contact).with('556698765432')
    expect(contact.reload.bsuid).to eq(payload[:user_id])
    expect(channel.inbox.contact_inboxes.where(contact: contact).pluck(:source_id))
      .to contain_exactly(stale_lid, payload[:user_id], '5566998765432')
  end
end
