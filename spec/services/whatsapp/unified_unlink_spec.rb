require 'rails_helper'

# Administrative unlink contract, not a reverse historical split. Real DB records,
# provider ingestion, builder and send service; only external IO is instrumented.
# Do not run alongside the main agent's specs: the main agent owns the test DB.
# Gap examples are ordinary regressions, not pending/xfail assertions.
# rubocop:disable RSpec/AnyInstance, RSpec/SpecFilePathFormat
RSpec.describe Whatsapp::UnifiedTransportService, type: :request do
  receipt_states = [[:meta, 'read'], [:uno, 'sent']].freeze
  reactivation_options = [false, true].freeze
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:suffix) { SecureRandom.random_number(10**7).to_s.rjust(7, '0') }
  let(:meta) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: "+55659#{suffix}",
                              sync_templates: false, validate_provider_config: false)
  end
  let(:uno) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: "+556599#{suffix}",
                              sync_templates: false, validate_provider_config: false)
  end
  let(:channels) { { meta: meta, uno: uno } }
  let(:contact) { create(:contact, account: account, name: 'Contato preservado', phone_number: '+5565987654321') }
  let!(:meta_alias) { create(:contact_inbox, inbox: meta.inbox, contact: contact, source_id: '556587654321') }
  let!(:uno_alias) { create(:contact_inbox, inbox: uno.inbox, contact: contact, source_id: '5565987654321') }
  let(:public_messages) { account.messages.where(message_type: %i[incoming outgoing], private: false) }

  around do |example|
    previous_network_configuration = WebMock::Config.instance.allow_net_connect
    previous_localhost_configuration = WebMock::Config.instance.allow_localhost
    WebMock.disable_net_connect!(allow_localhost: false)
    travel_to(Time.at(1_792_151_940).utc) { example.run }
  ensure
    WebMock::Config.instance.allow_net_connect = previous_network_configuration
    WebMock::Config.instance.allow_localhost = previous_localhost_configuration
  end

  # These helpers remove repeated fixture envelope rewriting/provider dispatch,
  # not the persistence or routing behavior under test.
  def webhook(provider, name)
    payload = JSON.parse(Rails.root.join('spec/fixtures/whatsapp_coexistence', "#{provider}_#{name}.json").read).with_indifferent_access
    channel = channels.fetch(provider)
    value = payload.dig(:entry, 0, :changes, 0, :value)
    value[:metadata].merge!(display_phone_number: channel.phone_number.delete_prefix('+'),
                            phone_number_id: channel.provider_config['phone_number_id'])
    Array(value[:message_echoes]).each { |event| event[:from] = channel.phone_number.delete_prefix('+') }
    payload[:phone_number] = channel.phone_number
    payload
  end

  def ingest(provider, payload)
    service = provider == :meta ? Whatsapp::IncomingMessageWhatsappCloudService : Whatsapp::IncomingMessageUnoapiService
    echo = payload.dig(:entry, 0, :changes, 0, :field) == 'smb_message_echoes'
    service.new(inbox: channels.fetch(provider).inbox, params: payload, outgoing_echo: echo).perform
  end

  %i[meta uno].each do |principal|
    context "with #{principal} as principal" do
      let!(:link) do
        WhatsappInboxLink.create!(account: account, primary_inbox: channels.fetch(principal).inbox,
                                  secondary_inbox: channels.fetch(principal == :meta ? :uno : :meta).inbox,
                                  default_provider: principal == :meta ? 'unoapi' : 'whatsapp_cloud', enabled: true)
      end
      let(:conversation) do
        create(:conversation, account: account, inbox: link.primary_inbox, contact: contact,
                              contact_inbox: principal == :meta ? meta_alias : uno_alias)
      end

      it 'administratively disables idempotently without splitting history or deleting identities, aliases or files' do
        ingest(:meta, webhook(:meta, 'phone_incoming'))
        ingest(:uno, webhook(:uno, 'phone_incoming'))
        canonical = public_messages.sole
        note = create(:message, account: account, inbox: canonical.inbox, conversation: canonical.conversation,
                                message_type: :outgoing, private: true, content: 'Nota interna preservada')
        legacy_conversation = create(:conversation, account: account, inbox: link.secondary_inbox, contact: contact,
                                                    contact_inbox: principal == :meta ? uno_alias : meta_alias)
        legacy = create(:message, account: account, inbox: link.secondary_inbox, conversation: legacy_conversation,
                                  source_id: 'legacy-public-id', created_at: 2.days.ago)
        allow(ActiveStorage::Blob.service).to receive(:upload)
        attachment = canonical.attachments.create!(account_id: account.id, file_type: :image,
                                                   file: fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png'))
        records = [canonical, note, legacy, canonical.conversation, legacy_conversation, contact, meta_alias, uno_alias, attachment,
                   attachment.file.attachment, attachment.file.blob,
                   *WhatsappUnifiedMessage.where(whatsapp_inbox_link: link),
                   *WhatsappUnifiedMessageAlias.joins(:whatsapp_message_identity).where(whatsapp_message_identities: { account_id: account.id }),
                   *WhatsappMessageIdentity.where(account: account)]
        snapshots = records.index_with { |record| record.reload.attributes }
        cutoff = link.activated_at
        account.enable_features!('inbox_management')
        headers = admin.create_new_auth_token

        2.times do
          delete "/api/v1/accounts/#{account.id}/inboxes/#{link.secondary_inbox_id}/whatsapp_link", headers: headers
          expect(response).to have_http_status(:ok)
          expect(link.reload).not_to be_enabled
          snapshots.each { |record, attributes| expect(record.reload.attributes).to eq(attributes) }
        end

        expect(link.activated_at).to eq(cutoff)
        expect(WhatsappInboxLink.for_inbox(meta.inbox)).to be_nil
        expect(WhatsappInboxLink.for_inbox(uno.inbox)).to be_nil
        expect(public_messages.reorder(:id).pluck(:id)).to eq([canonical.id, legacy.id].sort)
      end

      it 'sends newly composed messages through each independent inbox after disable, without unified metadata' do
        link.update!(enabled: false)
        attempts = []
        allow_any_instance_of(Channel::Whatsapp).to receive(:send_message) do |channel, _recipient, message|
          attempts << [channel.id, message.id]
          "independent-#{channel.id}"
        end

        channels.each do |provider, channel|
          independent = create(:conversation, account: account, inbox: channel.inbox, contact: contact,
                                              contact_inbox: provider == :meta ? meta_alias : uno_alias)
          create(:message, account: account, inbox: channel.inbox, conversation: independent,
                           sender: contact, message_type: :incoming)
          outgoing = Messages::MessageBuilder.new(admin, independent,
                                                  ActionController::Parameters.new(content: 'Envio independente', message_type: 'outgoing')).perform
          expect(outgoing.reload.content_attributes['whatsapp_transport']).to be_blank
          Whatsapp::SendOnWhatsappService.new(message: outgoing).perform
          expect(outgoing.reload.source_id).to eq("independent-#{channel.id}")
          expect(attempts.last).to eq([channel.id, outgoing.id])
        end

        expect(attempts.map(&:first)).to eq([meta.id, uno.id])
      end

      it 'rejects a stale explicit transport selection after disable instead of silently using the inbox default' do
        current_conversation = conversation
        link.update!(enabled: false)
        expect do
          Messages::MessageBuilder.new(admin, current_conversation,
                                       ActionController::Parameters.new(content: 'Seleção antiga', whatsapp_transport: 'unoapi')).perform
        end.to raise_error(ArgumentError, /enabled inbox link/)
        expect(current_conversation.messages.outgoing).to be_empty
      end

      it 'rejects an already queued unified send without trying either transport or rewriting its metadata' do
        outgoing = Messages::MessageBuilder.new(admin, conversation,
                                                ActionController::Parameters.new(content: 'Pendente', whatsapp_transport: 'unoapi')).perform
        metadata = outgoing.reload.content_attributes.deep_dup
        link.update!(enabled: false)
        expect_any_instance_of(Channel::Whatsapp).not_to receive(:send_message)
        expect_any_instance_of(Channel::Whatsapp).not_to receive(:send_template)

        expect { Whatsapp::SendOnWhatsappService.new(message: outgoing.reload).perform }
          .to raise_error(ArgumentError, /review the pending message/)
        expect(outgoing.reload.content_attributes).to eq(metadata)
        expect(outgoing.source_id).to be_blank
      end

      it 'does not revive a queued send from the previous activation when the same link is enabled again' do
        outgoing = Messages::MessageBuilder.new(admin, conversation,
                                                ActionController::Parameters.new(content: 'Ciclo anterior', whatsapp_transport: 'unoapi')).perform
        metadata = outgoing.reload.content_attributes.deep_dup
        link.update!(enabled: false)
        travel 1.hour
        link.update!(enabled: true)
        expect_any_instance_of(Channel::Whatsapp).not_to receive(:send_message)
        expect_any_instance_of(Channel::Whatsapp).not_to receive(:send_template)

        expect { Whatsapp::SendOnWhatsappService.new(message: outgoing.reload).perform }
          .to raise_error(ArgumentError, /review the pending message/)
        expect(outgoing.reload.content_attributes).to eq(metadata)
        expect(outgoing.source_id).to be_blank
      end

      it 'continues mapping statuses and repeated known echoes to the existing canonical message after disable' do
        payloads = channels.keys.index_with { |provider| webhook(provider, 'phone_echo') }
        payloads.each { |provider, payload| ingest(provider, payload.deep_dup) }
        canonical = public_messages.sole
        original_source_id = canonical.source_id
        original_conversation_id = canonical.conversation_id
        alias_ids = WhatsappUnifiedMessageAlias.joins(:whatsapp_message_identity)
                                               .where(whatsapp_message_identities: { account_id: account.id }).order(:id).pluck(:id)
        link.update!(enabled: false)

        receipt_states.each do |provider, status|
          payload = payloads.fetch(provider).deep_dup
          change = payload[:entry].first[:changes].first
          echo = change[:value].delete(:message_echoes).first
          change[:field] = 'messages'
          change[:value][:statuses] = [{ id: echo[:id], provider_message_id: echo[:provider_message_id],
                                         recipient_id: '5565987654321', status: status, timestamp: Time.current.to_i.to_s }.compact]
          ingest(provider, payload)
          ingest(provider, payloads.fetch(provider).deep_dup)
          expect(canonical.reload.status).to eq('read')
        end

        expect(public_messages.pluck(:id)).to eq([canonical.id])
        expect(canonical.reload).to have_attributes(source_id: original_source_id, conversation_id: original_conversation_id)
        expect(WhatsappUnifiedMessageAlias.where(id: alias_ids).count).to eq(alias_ids.size)
        expect(account.conversations.pluck(:id)).to eq([original_conversation_id])
      end

      reactivation_options.each do |reactivate|
        phase = reactivate ? 'after reactivation' : 'while disabled'
        it "does not duplicate a canonical echo with a previously unseen counterpart #{phase}" do
          ingest(principal, webhook(principal, 'phone_echo'))
          canonical = public_messages.sole
          original_attributes = canonical.attributes.except('updated_at', 'status')
          link.update!(enabled: false)
          if reactivate
            travel 1.hour
            link.update!(enabled: true)
          end
          partner = principal == :meta ? :uno : :meta

          2.times { ingest(partner, webhook(partner, 'phone_echo')) }

          expect(public_messages.pluck(:id)).to eq([canonical.id])
          expect(canonical.reload.attributes.except('updated_at', 'status')).to eq(original_attributes)
          identity = WhatsappMessageIdentity.find_by!(account: account, inbox: channels.fetch(partner).inbox)
          expect(Whatsapp::UnifiedMessageIngestionService.message_for(identity)&.id).to eq(canonical.id)
          expect(account.conversations.pluck(:id)).to eq([canonical.conversation_id])
        end

        it "keeps an old pending reservation for review without a legacy bubble #{reactivate ? 'after reactivation' : 'while disabled'}" do
          payload = webhook(principal, 'phone_echo')
          value = payload[:entry].first[:changes].first[:value]
          Whatsapp::MessageIdentityObservationService.new(inbox: link.primary_inbox, value: value, outgoing_echo: true).perform
          identity = WhatsappMessageIdentity.find_by!(account: account, inbox: link.primary_inbox)
          pending_record = WhatsappUnifiedMessage.create!(whatsapp_inbox_link: link, original_id: identity.provider_message_id,
                                                          direction: 'outgoing', participant_key: '5565987654321',
                                                          message_kind: 'text', state: 'pending')
          pending_record.aliases.create!(whatsapp_message_identity: identity)
          link.update!(enabled: false)
          if reactivate
            travel 1.hour
            link.update!(enabled: true)
          end

          ingest(principal, payload)

          expect(public_messages).to be_empty
          expect(account.conversations).to be_empty
          expect(pending_record.reload.message_id).to be_nil
          # An explicit durable review state, not merely an invisible pending retry.
          expect(pending_record.state).to eq('review')
          expect(pending_record.aliases.pluck(:whatsapp_message_identity_id)).to eq([identity.id])
        end

        phase = reactivate ? 'after reactivation' : 'while disabled'
        it "holds an old queued unified event for explicit review, not replay or an invisible disabled state #{phase}" do
          payload = webhook(principal, 'phone_echo')
          value = payload[:entry].first[:changes].first[:value]
          Whatsapp::MessageIdentityObservationService.new(inbox: link.primary_inbox, value: value, outgoing_echo: true).perform
          identity = WhatsappMessageIdentity.find_by!(account: account, inbox: link.primary_inbox)
          event = Whatsapp::UnifiedEventService.defer(link: link, identity: identity, value: value, reason: 'outbound_response_pending')
          original_payload = event.reload.payload.deep_dup
          link.update!(enabled: false)
          if reactivate
            travel 1.hour
            link.update!(enabled: true)
          end
          expect_any_instance_of(Channel::Whatsapp).not_to receive(:send_message)

          2.times { Whatsapp::UnifiedEventService.new(event: event.reload).perform }

          expect(event.reload.state).to eq('review')
          expect(event.reason).to eq('link_changed')
          expect(event.next_attempt_at).to be_nil
          expect(event.payload).to eq(original_payload)
          expect(public_messages).to be_empty
          expect(account.conversations).to be_empty
        end

        phase = reactivate ? 'after reactivation' : 'while disabled'
        it "rechecks a coordinator initialized before unlink and reviews the event without a legacy bubble #{phase}", :aggregate_failures do
          payload = webhook(principal, 'phone_echo')
          value = payload[:entry].first[:changes].first[:value]
          Whatsapp::MessageIdentityObservationService.new(inbox: link.primary_inbox, value: value, outgoing_echo: true).perform
          identity = WhatsappMessageIdentity.find_by!(account: account, inbox: link.primary_inbox)
          coordinator = Whatsapp::UnifiedMessageIngestionService.new(inbox: link.primary_inbox, value: value)
          original_cutoff = link.activated_at
          expect(coordinator.link).to be_enabled
          expect(coordinator.link.activated_at).to eq(original_cutoff)
          legacy_ingestion_called = false

          link.update!(enabled: false)
          if reactivate
            travel 1.hour
            link.update!(enabled: true)
          end

          2.times do
            coordinator.perform do
              legacy_ingestion_called = true
              # Exercise real provider ingestion if a stale coordinator wrongly
              # releases the event to its caller instead of holding it for review.
              ingest(principal, payload.deep_dup)
            end
          end

          expect(legacy_ingestion_called).to be(false)
          expect(public_messages).to be_empty
          expect(account.conversations).to be_empty
          expect(WhatsappUnifiedMessage.where(whatsapp_inbox_link: link)).to be_empty
          event = WhatsappUnifiedEvent.where(whatsapp_inbox_link: link, whatsapp_message_identity: identity).sole
          expect(event).to have_attributes(state: 'review', reason: 'link_changed', next_attempt_at: nil)
          expect(event.payload).to eq(value.deep_stringify_keys)
          expect(Whatsapp::UnifiedMessageIngestionService.message_for(identity)).to be_nil
        end
      end

      it 'maps a late BSUID counterpart after unlink to the canonical contact without a new technical contact' do
        ingest(:uno, webhook(:uno, 'bsuid_echo'))
        canonical = public_messages.sole
        link.update!(enabled: false)

        2.times { ingest(:meta, webhook(:meta, 'bsuid_echo')) }

        expect(public_messages.pluck(:id)).to eq([canonical.id])
        expect(account.contacts.pluck(:id)).to eq([contact.id])
        expect(meta.inbox.contact_inboxes.find_by!(source_id: 'BR.1234567890123456').contact_id).to eq(contact.id)
      end

      it 'sets a fresh activation cutoff and does not replay a known pre-cutoff canonical event' do
        payload = webhook(principal, 'phone_incoming')
        ingest(principal, payload.deep_dup)
        canonical = public_messages.sole
        old_cutoff = link.activated_at
        link.update!(enabled: false)
        travel 1.hour
        link.update!(enabled: true)

        expect(link.reload.activated_at).to be > old_cutoff
        expect { 2.times { ingest(principal, payload.deep_dup) } }.not_to change(public_messages, :count)
        expect(public_messages.pluck(:id)).to eq([canonical.id])
        expect(account.conversations.pluck(:id)).to eq([canonical.conversation_id])
      end
    end
  end
end
# rubocop:enable RSpec/AnyInstance, RSpec/SpecFilePathFormat
