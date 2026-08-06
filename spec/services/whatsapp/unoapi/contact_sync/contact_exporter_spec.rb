require 'rails_helper'

describe Whatsapp::Unoapi::ContactSync::ContactExporter do
  subject(:exporter) { described_class.new(channel: channel, contact: contact, client: client) }

  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'unoapi',
      contact_sync_enabled: true,
      contact_export_enabled: true,
      sync_templates: false,
      validate_provider_config: false
    )
  end
  let(:contact) do
    create(
      :contact,
      account: account,
      name: 'Fran Fernandes',
      phone_number: '+5566999069708',
      bsuid: '53515477086263@lid',
      whatsapp_username: 'fran'
    )
  end
  let!(:contact_inbox) do
    create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: '5566999069708')
  end
  let(:client) { instance_double(Whatsapp::Unoapi::ContactSync::Client) }
  let(:response) do
    {
      'success' => true,
      'contact' => {
        'phone_number' => '556699069708',
        'full_name' => 'Fran Fernandes',
        'first_name' => 'Fran',
        'user_id' => '53515477086263@lid',
        'username' => 'fran'
      }
    }
  end

  before do
    allow(client).to receive(:verify_contact).and_return(
      'input' => '5566999069708',
      'wa_id' => '556699069708',
      'user_id' => '53515477086263@lid',
      'status' => 'valid'
    )
    allow(client).to receive(:import_contact).and_return(response)
  end

  it 'exports an inbox contact once and persists the canonical identity returned by UnoAPI' do # rubocop:disable RSpec/MultipleExpectations
    expect(exporter.perform).to eq(:processed)
    expect(client).to have_received(:import_contact).with(
      phone_number: '5566999069708',
      full_name: 'Fran Fernandes',
      first_name: 'Fran',
      user_id: '53515477086263@lid',
      username: 'fran'
    ).once
    expect(contact.reload.phone_number).to eq('+5566999069708')
    expect(channel.inbox.contact_inboxes.where(contact: contact).pluck(:source_id))
      .to contain_exactly('5566999069708', '53515477086263@lid')
    expect(contact_inbox.reload.additional_attributes.fetch('unoapi_contact_export')).to include(
      'status' => 'exported',
      'phone_number' => '556699069708',
      'user_id' => '53515477086263@lid'
    )

    expect(exporter.perform).to eq(:skipped)
    expect(client).to have_received(:verify_contact).once
    expect(client).to have_received(:import_contact).once
  end

  it 'does not export a contact already found during the inbound synchronization' do
    contact_inbox.update!(additional_attributes: { 'unoapi_last_updated_ms' => 1_784_977_424_000 })

    expect(exporter.perform).to eq(:skipped)
    expect(client).not_to have_received(:verify_contact)
    expect(client).not_to have_received(:import_contact)
  end

  it 'skips a technical numeric identifier stored as an invalid phone' do
    contact.update_columns(phone_number: '+106657677844519') # rubocop:disable Rails/SkipsModelValidations

    expect(exporter.perform).to eq(:skipped)
    expect(client).not_to have_received(:verify_contact)
    expect(client).not_to have_received(:import_contact)
  end

  it 'replaces a stale local LID with the identity validated by the WhatsApp network' do # rubocop:disable RSpec/MultipleExpectations
    stale_lid = '99226763698235@lid'
    channel.inbox.update!(lock_to_single_conversation: true)
    contact.update!(bsuid: stale_lid)
    stale_link = create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: stale_lid)
    phone_conversation = create(
      :conversation,
      account: account,
      inbox: channel.inbox,
      contact: contact,
      contact_inbox: contact_inbox,
      last_activity_at: 2.days.ago
    )
    stale_conversation = create(
      :conversation,
      account: account,
      inbox: channel.inbox,
      contact: contact,
      contact_inbox: stale_link,
      last_activity_at: 1.day.ago
    )
    stale_message = create(:message, account: account, inbox: channel.inbox, conversation: stale_conversation, sender: contact)
    other_channel = create(
      :channel_whatsapp,
      account: account,
      provider: 'unoapi',
      sync_templates: false,
      validate_provider_config: false
    )
    create(:contact_inbox, inbox: other_channel.inbox, contact: contact, source_id: stale_lid)

    expect(exporter.perform).to eq(:processed)
    expect(contact.reload.bsuid).to eq('53515477086263@lid')
    expect(channel.inbox.contact_inboxes.where(contact: contact).pluck(:source_id))
      .to contain_exactly('5566999069708', '53515477086263@lid')
    expect(other_channel.inbox.contact_inboxes.where(contact: contact).pluck(:source_id))
      .to contain_exactly('53515477086263@lid')
    expect(stale_message.reload.conversation).to eq(phone_conversation)
    expect(channel.inbox.conversations.where(contact: contact).count).to eq(1)
    expect(Conversation.exists?(stale_conversation.id)).to be(false)
    expect(client).to have_received(:import_contact).with(hash_including(
                                                            phone_number: '5566999069708',
                                                            user_id: '53515477086263@lid'
                                                          ))
  end

  it 'merges a legacy duplicate with the same phone before persisting the verified identity' do
    duplicate = create(:contact, account: account, phone_number: '+5566999999999')
    duplicate.update_columns(phone_number: contact.phone_number) # rubocop:disable Rails/SkipsModelValidations

    expect(exporter.perform).to eq(:processed)
    expect(Contact.exists?(duplicate.id)).to be(false)
    expect(contact.reload.phone_number).to eq('+5566999069708')
    expect(client).to have_received(:import_contact)
  end

  it 'normalizes the base phone before merging a network-confirmed mobile contact' do
    contact.update_columns(phone_number: '+556696057870') # rubocop:disable Rails/SkipsModelValidations
    contact_inbox.update_columns(source_id: '556696057870') # rubocop:disable Rails/SkipsModelValidations
    mobile_contact = create(
      :contact,
      account: account,
      phone_number: '+5566996057870',
      bsuid: '19654022004956@lid'
    )
    allow(client).to receive(:verify_contact).and_return(
      'wa_id' => '556696057870',
      'user_id' => '19654022004956@lid',
      'status' => 'valid'
    )

    expect(exporter.perform).to eq(:processed)
    expect(Contact.exists?(mobile_contact.id)).to be(false)
    expect(contact.reload.phone_number).to eq('+5566996057870')
    expect(channel.inbox.contact_inboxes.where(contact: contact).pluck(:source_id))
      .to contain_exactly('5566996057870', '19654022004956@lid')
  end

  it 'removes the phone alias without the ninth digit when the canonical alias already exists' do
    create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: '556699069708')

    allow(client).to receive(:verify_contact).and_return(
      'wa_id' => '5566999069708',
      'user_id' => '53515477086263@lid',
      'status' => 'valid'
    )

    expect(exporter.perform).to eq(:processed)
    expect(channel.inbox.contact_inboxes.where(contact: contact).pluck(:source_id))
      .to contain_exactly('5566999069708', '53515477086263@lid')
  end

  it 'merges a technical LID-only contact confirmed by the WhatsApp network' do
    channel.inbox.update!(lock_to_single_conversation: true)
    lid_contact = create(:contact, account: account, name: '53515477086263@lid')
    lid_link = create(:contact_inbox, inbox: channel.inbox, contact: lid_contact, source_id: '53515477086263@lid')
    phone_conversation = create(:conversation, account: account, inbox: channel.inbox, contact: contact, contact_inbox: contact_inbox)
    lid_conversation = create(:conversation, account: account, inbox: channel.inbox, contact: lid_contact, contact_inbox: lid_link)
    lid_message = create(:message, account: account, inbox: channel.inbox, conversation: lid_conversation, sender: lid_contact)

    expect(exporter.perform).to eq(:processed)
    expect(Contact.exists?(lid_contact.id)).to be(false)
    expect(lid_message.reload.sender).to eq(contact)
    expect(lid_message.conversation).to eq(phone_conversation)
    expect(Conversation.exists?(lid_conversation.id)).to be(false)
  end

  it 'keeps separate conversations when the UnoAPI inbox does not lock contacts to one conversation' do
    channel.inbox.update!(lock_to_single_conversation: false)
    lid_contact = create(:contact, account: account, name: '53515477086263@lid')
    lid_link = create(:contact_inbox, inbox: channel.inbox, contact: lid_contact, source_id: '53515477086263@lid')
    create(:conversation, account: account, inbox: channel.inbox, contact: contact, contact_inbox: contact_inbox)
    lid_conversation = create(:conversation, account: account, inbox: channel.inbox, contact: lid_contact, contact_inbox: lid_link)

    expect(exporter.perform).to eq(:processed)
    expect(Contact.exists?(lid_contact.id)).to be(false)
    expect(channel.inbox.conversations.where(contact: contact).count).to eq(2)
    expect(Conversation.exists?(lid_conversation.id)).to be(true)
  end

  it 'uses the phone as name instead of exporting a technical JID' do
    contact.update!(name: '53515477086263@lid')

    expect(exporter.perform).to eq(:processed)
    expect(client).to have_received(:import_contact).with(hash_including(
                                                            full_name: '5566999069708',
                                                            first_name: '5566999069708'
                                                          ))
  end

  it 'marks a permanent rejection and does not post the same identity again' do
    allow(client).to receive(:import_contact)
      .and_raise(Whatsapp::Unoapi::ContactSync::Client::PermanentError, 'UnoAPI HTTP 400: invalid contact')

    expect(exporter.perform).to eq(:failed)
    expect(exporter.perform).to eq(:skipped)
    expect(client).to have_received(:import_contact).once
    expect(contact_inbox.reload.additional_attributes.dig('unoapi_contact_export', 'status')).to eq('failed')
  end
end
