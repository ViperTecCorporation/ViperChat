require 'rails_helper'
require 'base64'
require 'stringio'

RSpec.describe Whatsapp::UsernameProfileSyncService do
  let(:account) { create(:account) }
  let(:bsuid) { 'BR.1234567890123456' }
  let(:meta_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+5565991234567',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:uno_channel) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: '+556591234567',
                              provider_config: { 'api_key' => 'synthetic', 'url' => 'https://username.invalid' },
                              sync_templates: false, validate_provider_config: false)
  end
  let(:channels) { { meta: meta_channel, uno: uno_channel } }
  let(:contact) do
    create(:contact, account: account, name: 'Nome humano preservado', phone_number: '+5565987654321', bsuid: bsuid,
                     whatsapp_username: 'old.username', additional_attributes: { 'manual_reference' => 'keep' })
  end
  let(:public_messages) { account.messages.where(message_type: %i[incoming outgoing]) }

  around do |example|
    previous_network = WebMock::Config.instance.allow_net_connect
    previous_localhost = WebMock::Config.instance.allow_localhost
    WebMock.disable_net_connect!(allow_localhost: false)
    travel_to(Time.at(1_792_151_940).utc) { example.run }
  ensure
    WebMock::Config.instance.allow_net_connect = previous_network
    WebMock::Config.instance.allow_localhost = previous_localhost
  end

  # Keep the fixture's proven message IDs; change only the documented profile fields.
  def webhook(provider, kind, username: '@new.username')
    payload = JSON.parse(Rails.root.join('spec/fixtures/whatsapp_coexistence', "#{provider}_#{kind}.json").read).with_indifferent_access
    value = payload.dig(:entry, 0, :changes, 0, :value)
    channel = channels.fetch(provider)
    value[:metadata] = { phone_number_id: channel.provider_config['phone_number_id'], display_phone_number: channel.phone_number.delete_prefix('+') }
    if provider == :meta
      value[:contacts].first[:profile] = { name: 'Nome recebido, não substituir', username: username, country_code: 'BR' }.compact
      value[:contacts].first[:user_id] = bsuid
      value[:contacts].first[:wa_id] ||= ''
      Array(value[:messages]).each { |message| message[:from] ||= '' }
      Array(value[:message_echoes]).each { |message| message[:to] ||= '' }
    end
    Array(value[:message_echoes]).each { |message| message[:from] = channel.phone_number.delete_prefix('+') }
    payload
  end

  def ingest(provider, payload)
    service = provider == :meta ? Whatsapp::IncomingMessageWhatsappCloudService : Whatsapp::IncomingMessageUnoapiService
    echo = payload.dig(:entry, 0, :changes, 0, :field) == 'smb_message_echoes'
    service.new(inbox: channels.fetch(provider).inbox, params: payload, outgoing_echo: echo).perform
  end

  context 'with an established BSUID contact' do
    before { create(:contact_inbox, inbox: meta_channel.inbox, contact: contact, source_id: bsuid) }

    it 'preserves avatar synchronization for a proven status recipient without requiring a username' do
      ingest(:meta, webhook(:meta, 'bsuid_echo'))
      payload = webhook(:meta, 'bsuid_echo', username: nil)
      value = payload.dig(:entry, 0, :changes, 0, :value)
      echo = value.delete(:message_echoes).sole
      value[:contacts].sole[:profile].merge!(picture: 'https://cdn.example.com/known-avatar.jpg', picture_metadata: { etag: 'known-etag' })
      value[:statuses] = [{ id: echo[:id], recipient_id: '', recipient_user_id: bsuid, status: 'read', timestamp: echo[:timestamp] }]

      expect { ingest(:meta, payload) }.to have_enqueued_job(Avatar::AvatarFromUrlJob)
        .with(contact, 'https://cdn.example.com/known-avatar.jpg', { 'etag' => 'known-etag' })
      expect(contact.reload.whatsapp_username).to eq('@new.username')
      expect(account.contacts.count).to eq(1)
    end

    %w[bsuid_incoming bsuid_echo].each do |kind|
      it "refreshes #{kind} username on exact replay without changing human name, phone or public IDs" do
        first = webhook(:meta, kind)
        ingest(:meta, first)
        original = public_messages.sole.attributes
        preserved = contact.reload.attributes.slice('id', 'name', 'phone_number', 'bsuid', 'created_at')
        second = webhook(:meta, kind, username: '@changed.username')
        expect { ingest(:meta, second) }.not_to change(public_messages, :count)
        expect(contact.reload.whatsapp_username).to eq('@changed.username')
        expect(contact.additional_attributes).to include('manual_reference' => 'keep', 'social_whatsapp_user_name' => 'changed.username')
        expect(contact.attributes.slice(*preserved.keys)).to eq(preserved)
        expect(public_messages.sole.attributes).to eq(original)
      end
    end

    it 'does not clear an existing username when the profile omits it or sends an empty value' do
      ingest(:meta, webhook(:meta, 'bsuid_incoming'))
      [nil, ''].each { |username| ingest(:meta, webhook(:meta, 'bsuid_incoming', username: username)) }
      expect(contact.reload.whatsapp_username).to eq('@new.username')
    end

    it 'does not let empty receipt or echo arrays hide a real incoming username update' do
      ingest(:meta, webhook(:meta, 'bsuid_incoming'))
      payload = webhook(:meta, 'bsuid_incoming', username: '@empty.arrays')
      payload.dig(:entry, 0, :changes, 0, :value).merge!(statuses: [], message_echoes: [])
      ingest(:meta, payload)
      expect(contact.reload.whatsapp_username).to eq('@empty.arrays')
      expect(public_messages.count).to eq(1)
    end

    it 'updates a status recipient from its matching profile, not the first contact in the receipt' do
      ingest(:meta, webhook(:meta, 'bsuid_echo'))
      other = create(:contact, account: account, bsuid: 'user.unrelated', whatsapp_username: 'untouched')
      payload = webhook(:meta, 'bsuid_echo', username: '@receipt.username')
      value = payload.dig(:entry, 0, :changes, 0, :value)
      echo = value.delete(:message_echoes).sole
      payload[:entry].first[:changes].first[:field] = 'messages'
      value[:statuses] = [{ id: echo[:id], recipient_id: '', recipient_user_id: bsuid, status: 'read', timestamp: echo[:timestamp] }]
      value[:contacts].unshift({ user_id: other.bsuid, wa_id: '', profile: { name: 'Wrong role', username: '@wrong.username' } })
      original_counts = [account.contacts.count, public_messages.count]
      ingest(:meta, payload)
      expect(contact.reload.whatsapp_username).to eq('@receipt.username')
      expect(contact.name).to eq('Nome humano preservado')
      expect(other.reload.whatsapp_username).to eq('untouched')
      expect([account.contacts.count, public_messages.count]).to eq(original_counts)
    end

    it 'ignores profiles with a different BSUID even when the message ID and username are familiar' do
      ingest(:meta, webhook(:meta, 'bsuid_incoming'))
      payload = webhook(:meta, 'bsuid_incoming', username: '@must.not.apply')
      payload.dig(:entry, 0, :changes, 0, :value, :contacts).sole[:user_id] = 'user.other'
      ingest(:meta, payload)
      expect(contact.reload.whatsapp_username).to eq('@new.username')
      expect(account.contacts.count).to eq(1)
    end

    it 'does not apply an unspecified status contact to an existing message' do
      ingest(:meta, webhook(:meta, 'bsuid_echo'))
      payload = webhook(:meta, 'bsuid_echo', username: '@must.not.apply')
      value = payload.dig(:entry, 0, :changes, 0, :value)
      echo = value.delete(:message_echoes).sole
      value[:statuses] = [{ id: echo[:id], recipient_id: '', status: 'read', timestamp: echo[:timestamp] }]
      ingest(:meta, payload)
      expect(contact.reload.whatsapp_username).to eq('@new.username')
      expect(account.contacts.count).to eq(1)
    end
  end

  it 'does not merge two supported BSUIDs when a username is reused' do
    %w[BR.1234567890123456 BR.9876543210987654].each_with_index do |user_id, index|
      payload = webhook(:meta, 'bsuid_incoming', username: '@same.username')
      value = payload.dig(:entry, 0, :changes, 0, :value)
      value[:contacts].sole[:user_id] = user_id
      value[:messages].sole.merge!(from_user_id: user_id, id: "wamid.username-collision-#{index}")
      ingest(:meta, payload)
    end
    expect(account.contacts.count).to eq(2)
    expect(account.contacts.pluck(:whatsapp_username)).to eq(%w[@same.username @same.username])
    expect(account.contacts.pluck(:phone_number)).to eq([nil, nil])
  end

  it 'preserves user.hash as an opaque non-phone ID, without merging reused usernames' do
    hash_id = 'user.9373795779eb6441c8adb2eaee5b848e7dd174ddd302d7db62142f4722d574b6'
    other_hash_id = "user.#{'a' * 64}"
    [hash_id, other_hash_id].each_with_index do |user_id, index|
      payload = webhook(:meta, 'bsuid_incoming', username: '@same.username')
      value = payload.dig(:entry, 0, :changes, 0, :value)
      value[:contacts].sole[:user_id] = user_id
      value[:messages].sole.merge!(from_user_id: user_id, id: "wamid.username-opaque-#{index}")
      ingest(:meta, payload)
    end
    expect(account.contacts.count).to eq(2)
    expect(account.contacts.pluck(:whatsapp_username)).to eq(%w[@same.username @same.username])
    expect(account.contacts.pluck(:phone_number)).to eq([nil, nil])
    expect(meta_channel.inbox.contact_inboxes.pluck(:source_id)).to contain_exactly(hash_id, other_hash_id)
    expect(Whatsapp::MetaMessageIdAdapter.parse('wamid.username-opaque-0')).to be_nil
  end

  %i[meta uno].each do |principal|
    [%i[meta uno], %i[uno meta]].each do |arrival_order|
      context "with #{principal} principal and #{arrival_order.join(' then ')}" do
        before do
          create(:contact_inbox, inbox: meta_channel.inbox, contact: contact, source_id: bsuid)
          create(:contact_inbox, inbox: uno_channel.inbox, contact: contact, source_id: '5565987654321')
          WhatsappInboxLink.create!(account: account, primary_inbox: channels.fetch(principal).inbox,
                                    secondary_inbox: channels.fetch(principal == :meta ? :uno : :meta).inbox,
                                    default_provider: 'whatsapp_cloud', enabled: true, activated_at: 1.day.ago)
        end

        %w[bsuid_incoming bsuid_echo].each do |kind|
          it "refreshes the mapped #{kind} contact without adding contacts, messages or media" do
            payloads = channels.keys.index_with { |provider| webhook(provider, kind) }
            arrival_order.each { |provider| ingest(provider, payloads.fetch(provider).deep_dup) }
            original = public_messages.sole.attributes
            counts = [account.contacts.count, public_messages.count, Attachment.count, ActiveStorage::Blob.count]
            ingest(:meta, webhook(:meta, kind, username: '@mapped.username'))
            expect(contact.reload.whatsapp_username).to eq('@mapped.username')
            expect(contact).to have_attributes(name: 'Nome humano preservado', phone_number: '+5565987654321', bsuid: bsuid)
            expect([account.contacts.count, public_messages.count, Attachment.count, ActiveStorage::Blob.count]).to eq(counts)
            expect(public_messages.sole.attributes).to eq(original)
            expect(public_messages.sole.inbox_id).to eq(channels.fetch(principal).inbox.id)
          end
        end

        it 'updates a BSUID-only receipt profile when the canonical contact retains its Uno LID' do
          contact.update!(bsuid: '123456789876543@lid')
          payloads = channels.keys.index_with { |provider| webhook(provider, 'bsuid_echo') }
          arrival_order.each { |provider| ingest(provider, payloads.fetch(provider).deep_dup) }
          payload = webhook(:meta, 'bsuid_echo', username: '@receipt.mapped')
          value = payload.dig(:entry, 0, :changes, 0, :value)
          echo = value.delete(:message_echoes).sole
          value[:statuses] = [{ id: echo[:id], recipient_id: '', recipient_user_id: bsuid, status: 'read', timestamp: echo[:timestamp] }]
          counts = [account.contacts.count, public_messages.count, Attachment.count, ActiveStorage::Blob.count]
          ingest(:meta, payload)
          expect(contact.reload).to have_attributes(whatsapp_username: '@receipt.mapped', bsuid: '123456789876543@lid')
          expect([account.contacts.count, public_messages.count, Attachment.count, ActiveStorage::Blob.count]).to eq(counts)
        end
      end
    end
  end

  it 'keeps business_username_updates audit-only without changing contacts or channel configuration' do
    original = meta_channel.provider_config.deep_dup
    contact
    params = { phone_number: meta_channel.phone_number,
               entry: [{ id: meta_channel.provider_config['business_account_id'],
                         changes: [{ field: 'business_username_updates', value: { username: '@business.new' } }] }] }
    event = Whatsapp::ManagementWebhookService.new(params: params).perform.sole
    expect(event.state).to eq('recorded')
    expect(contact.reload.whatsapp_username).to eq('old.username')
    expect(meta_channel.reload.provider_config).to eq(original)
  end

  it 'preserves Uno receipt contacts and their existing identifier-sync path without invoking Meta profile sync' do
    create(:contact_inbox, inbox: uno_channel.inbox, contact: contact, source_id: '5565987654321')
    payload = webhook(:uno, 'bsuid_echo')
    ingest(:uno, payload)
    value = payload.dig(:entry, 0, :changes, 0, :value)
    echo = value.delete(:message_echoes).sole
    value[:statuses] = [{ id: echo[:id], provider_message_id: echo[:provider_message_id], recipient_id: '5565987654321',
                         status: 'read', timestamp: echo[:timestamp] }]
    value[:contacts].sole[:user_id] = '123456789876543@lid'
    expect(described_class).not_to receive(:new)
    ingest(:uno, payload)
    expect(uno_channel.inbox.contact_inboxes.find_by!(source_id: '123456789876543@lid').contact_id).to eq(contact.id)
    expect(contact.reload.whatsapp_username).to eq('old.username')
    expect(value[:contacts]).to be_present
  end

  it 'does not resolve an unfamiliar wamid or a different account by username' do
    create(:contact_inbox, inbox: meta_channel.inbox, contact: contact, source_id: bsuid)
    payload = webhook(:meta, 'bsuid_incoming', username: '@must.not.apply')
    value = payload.dig(:entry, 0, :changes, 0, :value)
    value[:messages].sole[:id] = 'wamid.unrecognized-username-contract'
    described_class.new(inbox: meta_channel.inbox, value: value).perform
    other = create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    described_class.new(inbox: other.inbox, value: value).perform
    expect(contact.reload.whatsapp_username).to eq('old.username')
    expect(public_messages).to be_empty
    expect(account.contacts.pluck(:id)).to eq([contact.id])
    expect(other.account.contacts).to be_empty
  end
end
