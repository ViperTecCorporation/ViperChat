require 'rails_helper'

# Real persisted scopes and identities parsed from provider fixtures. No fabricated
# identity observations or mocked ingestion/replay; only media HTTP is a boundary.
RSpec.describe Whatsapp::UnifiedEventService do
  directions = %w[incoming echo].freeze
  terminal_states = %w[completed disabled review].freeze
  recheck_states = %w[completed disabled pending].freeze
  let(:account) { create(:account) }
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
  let(:provider) { :meta }
  let(:fixture_name) { 'phone_incoming' }
  let(:channel) { channels.fetch(provider) }
  let(:value) do
    payload = JSON.parse(Rails.root.join('spec/fixtures/whatsapp_coexistence', "#{provider}_#{fixture_name}.json").read)
    payload.dig('entry', 0, 'changes', 0, 'value').with_indifferent_access.tap do |body|
      body[:metadata].merge!(display_phone_number: channel.phone_number.delete_prefix('+'),
                             phone_number_id: channel.provider_config['phone_number_id'])
      Array(body[:message_echoes]).each { |echo| echo[:from] = channel.phone_number.delete_prefix('+') }
    end
  end
  let(:identity) do
    Whatsapp::MessageIdentityObservationService.new(inbox: channel.inbox, value: value,
                                                    outgoing_echo: value[:message_echoes].present?).perform
    external_id = Array(value[:messages] || value[:message_echoes]).first.fetch(:id)
    WhatsappMessageIdentity.find_by!(inbox: channel.inbox, external_id: external_id)
  end
  let(:reason) { 'identity_pending' }
  let(:event) { described_class.defer(link: link, identity: identity, value: value, reason: reason) }

  around do |example|
    previous_network_configuration = WebMock::Config.instance.allow_net_connect
    previous_localhost_configuration = WebMock::Config.instance.allow_localhost
    WebMock.disable_net_connect!(allow_localhost: false)
    travel_to(Time.at(1_792_151_940).utc) { example.run }
  ensure
    WebMock::Config.instance.allow_net_connect = previous_network_configuration
    WebMock::Config.instance.allow_localhost = previous_localhost_configuration
  end

  %i[meta uno].each do |principal|
    context "with #{principal} as principal" do
      let!(:link) do
        WhatsappInboxLink.create!(account: account, primary_inbox: channels.fetch(principal).inbox,
                                  secondary_inbox: channels.fetch(principal == :meta ? :uno : :meta).inbox,
                                  default_provider: 'whatsapp_cloud', enabled: true)
      end

      %i[meta uno].each do |observed_provider|
        directions.each do |direction|
          context "with a real #{observed_provider} #{direction} identity" do
            let(:provider) { observed_provider }
            let(:fixture_name) { "phone_#{direction}" }

            it 'persists one holding record and schedules its first retry in fifteen seconds' do
              original = event
              clear_enqueued_jobs
              3.times do
                expect(described_class.defer(link: link, identity: identity, value: value, reason: reason).id).to eq(original.id)
              end

              expect(original.reload).to have_attributes(state: 'pending', reason: reason, attempts: 0,
                                                         activation_cutoff: link.activated_at, next_attempt_at: 15.seconds.from_now)
              expect(original.payload).to eq(value.deep_stringify_keys)
              expect(WhatsappUnifiedEvent.where(whatsapp_inbox_link: link, whatsapp_message_identity: identity).count).to eq(1)
              expect(Whatsapp::ProcessUnifiedEventJob).not_to have_been_enqueued
              expect(account.contacts).to be_empty
              expect(account.messages).to be_empty
            end

            it 'enqueues only the new durable row with its database ID' do
              observed_identity = identity
              clear_enqueued_jobs
              expect do
                described_class.defer(link: link, identity: observed_identity, value: value, reason: reason)
              end.to have_enqueued_job(Whatsapp::ProcessUnifiedEventJob).with(kind_of(Integer)).at(15.seconds.from_now)
            end

            it 'completes from the persisted canonical alias, not the provider perform return value' do
              contact = create(:contact, account: account, phone_number: '+5565987654321')
              create(:contact_inbox, inbox: meta.inbox, contact: contact, source_id: '556587654321')
              create(:contact_inbox, inbox: uno.inbox, contact: contact, source_id: '5565987654321')
              stored = event
              travel 16.seconds
              Whatsapp::ProcessUnifiedEventJob.perform_now(stored.id)
              message = account.messages.where(message_type: %i[incoming outgoing]).sole
              expect(Whatsapp::UnifiedMessageIngestionService.message_for(identity).id).to eq(message.id)
              expect(stored.reload).to have_attributes(state: 'completed', reason: 'correlated', payload: {}, next_attempt_at: nil)
              expect(message.inbox_id).to eq(link.primary_inbox_id)
              expect(message.conversation.contact_id).to eq(contact.id)
              snapshot = stored.attributes
              2.times { Whatsapp::ProcessUnifiedEventJob.perform_now(stored.id) }
              expect(stored.reload.attributes).to eq(snapshot)
              expect(account.messages.where(message_type: %i[incoming outgoing]).pluck(:id)).to eq([message.id])
            end

            terminal_states.each do |terminal_state|
              it "does not replay a #{terminal_state} row even when explicitly invoked repeatedly" do
                stored = event
                stored.update!(state: terminal_state, next_attempt_at: nil)
                snapshot = stored.reload.attributes
                clear_enqueued_jobs
                2.times { Whatsapp::ProcessUnifiedEventJob.perform_now(stored.id) }

                expect(stored.reload.attributes).to eq(snapshot)
                expect(account.contacts).to be_empty
                expect(account.messages).to be_empty
                expect(Whatsapp::ProcessUnifiedEventJob).not_to have_been_enqueued
              end
            end
          end
        end
      end

      context 'with an unresolved BSUID from the real adapter' do
        let(:fixture_name) { 'bsuid_incoming' }

        it 'leaves insufficient evidence in review after the automatic retry without inventing a contact' do
          stored = event
          stored.update!(state: 'review', attempts: 12, next_attempt_at: nil)
          travel 5.minutes
          clear_enqueued_jobs
          Whatsapp::RecheckUnifiedEventsJob.perform_now
          expect(Whatsapp::ProcessUnifiedEventJob).to have_been_enqueued.with(stored.id).once
          Whatsapp::ProcessUnifiedEventJob.perform_now(stored.id)
          expect(stored.reload).to have_attributes(state: 'review', attempts: 13, next_attempt_at: nil)
          expect(stored.payload).to be_present
          expect(account.contacts).to be_empty
          expect(account.messages).to be_empty
          clear_enqueued_jobs
          Whatsapp::RecheckUnifiedEventsJob.perform_now
          expect(Whatsapp::ProcessUnifiedEventJob).not_to have_been_enqueued
        end

        it 'ignores an explicit job before the first due time without consuming an attempt' do
          stored = event
          snapshot = stored.attributes
          3.times { Whatsapp::ProcessUnifiedEventJob.perform_now(stored.id) }
          expect(stored.reload.attributes).to eq(snapshot)
          expect(account.contacts).to be_empty
          expect(account.messages).to be_empty
          travel 16.seconds
          Whatsapp::ProcessUnifiedEventJob.perform_now(stored.id)
          expect(stored.reload).to have_attributes(state: 'pending', attempts: 1)
        end

        it 'makes the matching staged event due now when a real counterpart identity wakes it' do
          stored = event
          counterpart_payload = JSON.parse(Rails.root.join('spec/fixtures/whatsapp_coexistence/uno_bsuid_incoming.json').read)
          counterpart_value = counterpart_payload.dig('entry', 0, 'changes', 0, 'value')
          counterpart_value['metadata']['display_phone_number'] = uno.phone_number.delete_prefix('+')
          counterpart_value['metadata']['phone_number_id'] = uno.provider_config['phone_number_id']
          Whatsapp::MessageIdentityObservationService.new(inbox: uno.inbox, value: counterpart_value).perform
          counterpart_id = counterpart_value.fetch('messages').first.fetch('id')
          counterpart = WhatsappMessageIdentity.find_by!(inbox: uno.inbox, external_id: counterpart_id)
          clear_enqueued_jobs
          described_class.wake(counterpart)

          expect(stored.reload).to have_attributes(next_attempt_at: Time.current, attempts: 0, state: 'pending')
          expect(Whatsapp::ProcessUnifiedEventJob).to have_been_enqueued.with(stored.id)
          expect(account.contacts).to be_empty
          expect(account.messages).to be_empty
        end

        it 'backs off unresolved identity attempts and stops at twelve for review without creating a placeholder' do
          stored = event
          raw = stored.payload.deep_dup
          12.times do |index|
            travel_to(stored.reload.next_attempt_at)
            Whatsapp::ProcessUnifiedEventJob.perform_now(stored.id)
            expect(stored.reload.attempts).to eq(index + 1)
            if index < 11
              expect(stored).to have_attributes(state: 'pending', reason: 'identity_pending')
              expect(stored.next_attempt_at).to eq(Time.current + [15 * (2**(index + 1)), 3600].min.seconds)
            end
          end
          expect(stored.reload).to have_attributes(state: 'review', attempts: 12, next_attempt_at: nil, payload: raw)
          snapshot = stored.attributes
          Whatsapp::ProcessUnifiedEventJob.perform_now(stored.id)
          expect(stored.reload.attributes).to eq(snapshot)
          expect(account.contacts).to be_empty
          expect(account.messages).to be_empty
        end

        it 'requires manual review when the binding is disabled before replay' do
          stored = event
          link.update!(enabled: false)
          Whatsapp::ProcessUnifiedEventJob.perform_now(stored.id)

          expect(stored.reload).to have_attributes(state: 'review', reason: 'link_changed', next_attempt_at: nil, attempts: 0)
          expect(account.contacts).to be_empty
          expect(account.messages).to be_empty
        end

        it 'does not reuse a pending payload across disable/reactivate even for the same inbox pair' do
          stored = event
          original_cutoff = stored.activation_cutoff
          link.update!(enabled: false)
          travel 1.minute
          link.update!(enabled: true)
          expect(link.reload.activated_at).not_to eq(original_cutoff)
          Whatsapp::ProcessUnifiedEventJob.perform_now(stored.id)

          expect(stored.reload).to have_attributes(state: 'review', reason: 'link_changed', next_attempt_at: nil, attempts: 0)
          expect(account.contacts).to be_empty
          expect(account.messages).to be_empty
        end

        it 'queues due pending rows only, excluding future and terminal rows' do
          stored = event
          clear_enqueued_jobs
          Whatsapp::ProcessUnifiedEventJob.perform_now
          expect(Whatsapp::ProcessUnifiedEventJob).not_to have_been_enqueued
          travel 15.seconds
          expect { Whatsapp::ProcessUnifiedEventJob.perform_now }
            .to have_enqueued_job(Whatsapp::ProcessUnifiedEventJob).with(stored.id).once
          stored.update!(state: 'review')
          clear_enqueued_jobs
          Whatsapp::ProcessUnifiedEventJob.perform_now
          expect(Whatsapp::ProcessUnifiedEventJob).not_to have_been_enqueued
        end
      end

      context 'with a conflicting correlation requiring human review' do
        let(:reason) { 'correlation_conflict' }

        it 'rechecks retained evidence after five minutes and completes safely through normal ingestion', :aggregate_failures do
          contact = create(:contact, account: account, phone_number: '+5565987654321')
          create(:contact_inbox, inbox: meta.inbox, contact: contact, source_id: '556587654321')
          create(:contact_inbox, inbox: uno.inbox, contact: contact, source_id: '5565987654321')
          stored = event
          clear_enqueued_jobs
          travel 299.seconds
          Whatsapp::RecheckUnifiedEventsJob.perform_now
          expect(Whatsapp::ProcessUnifiedEventJob).not_to have_been_enqueued
          travel 1.second
          2.times { Whatsapp::RecheckUnifiedEventsJob.perform_now }
          expect(Whatsapp::ProcessUnifiedEventJob).to have_been_enqueued.with(stored.id).once
          expect(stored.reload.state).to eq('pending')
          2.times { Whatsapp::ProcessUnifiedEventJob.perform_now(stored.id) }
          message = account.messages.where(message_type: %i[incoming outgoing]).sole
          expect(stored.reload).to have_attributes(state: 'completed', reason: 'correlated', payload: {})
          expect(message.conversation.contact_id).to eq(contact.id)
          expect(Whatsapp::UnifiedMessageIngestionService.message_for(identity).id).to eq(message.id)
          expect(account.contacts.pluck(:id)).to eq([contact.id])
          expect(message.attachments).to be_empty
        end

        recheck_states.each do |state|
          it "never automatically reopens a #{state} event" do
            stored = event
            stored.update!(state: state)
            snapshot = stored.attributes
            clear_enqueued_jobs
            travel 5.minutes
            Whatsapp::RecheckUnifiedEventsJob.perform_now
            expect(stored.reload.attributes).to eq(snapshot)
            expect(Whatsapp::ProcessUnifiedEventJob).not_to have_been_enqueued
          end
        end

        it 'does not reuse an event from an earlier activation or a disabled inbox link' do
          stored = event
          link.update!(enabled: false)
          clear_enqueued_jobs
          travel 5.minutes
          Whatsapp::RecheckUnifiedEventsJob.perform_now
          link.update!(enabled: true)
          Whatsapp::RecheckUnifiedEventsJob.perform_now
          expect(stored.reload.state).to eq('review')
          expect(Whatsapp::ProcessUnifiedEventJob).not_to have_been_enqueued
        end

        it 'does not replay discarded payloads or reset the processing attempt count' do
          stored = event
          stored.update!(payload: {})
          clear_enqueued_jobs
          travel 5.minutes
          Whatsapp::RecheckUnifiedEventsJob.perform_now
          expect(Whatsapp::ProcessUnifiedEventJob).not_to have_been_enqueued
          stored.update!(payload: value, attempts: 12)
          travel 5.minutes
          Whatsapp::RecheckUnifiedEventsJob.perform_now
          expect(stored.reload).to have_attributes(state: 'pending', attempts: 12)
        end

        it 'rolls back a failed enqueue without exposing the webhook payload' do
          stored = event
          travel 5.minutes
          allow(Whatsapp::ProcessUnifiedEventJob).to receive(:perform_later).and_raise(IOError, 'private payload')
          allow(Rails.logger).to receive(:warn)
          expect { Whatsapp::RecheckUnifiedEventsJob.perform_now }.not_to raise_error
          expect(stored.reload.state).to eq('review')
          expect(Rails.logger).to have_received(:warn).with(
            { event: 'whatsapp_unified_event_recheck_failed', event_id: stored.id, error_class: 'IOError' }.to_json
          )
        end

        it 'retains the payload for review without scheduling or replaying it' do
          observed_identity = identity
          clear_enqueued_jobs
          stored = described_class.defer(link: link, identity: observed_identity, value: value, reason: reason)
          snapshot = stored.attributes
          2.times { Whatsapp::ProcessUnifiedEventJob.perform_now(stored.id) }

          expect(stored.reload).to have_attributes(state: 'review', reason: 'correlation_conflict', next_attempt_at: nil)
          expect(stored.payload).to eq(value.deep_stringify_keys)
          expect(stored.attributes).to eq(snapshot)
          expect(Whatsapp::ProcessUnifiedEventJob).not_to have_been_enqueued
          expect(account.contacts).to be_empty
          expect(account.messages).to be_empty
        end
      end

      context 'when the external media download repeatedly fails' do
        let(:fixture_name) { 'image_incoming' }

        it 'bounds real replay errors at twelve attempts and retains the raw payload for review' do
          contact = create(:contact, account: account, phone_number: '+5565987654321')
          create(:contact_inbox, inbox: meta.inbox, contact: contact, source_id: '556587654321')
          create(:contact_inbox, inbox: uno.inbox, contact: contact, source_id: '5565987654321')
          media_id = value.dig(:messages, 0, :image, :id)
          stub_request(:get, meta.media_url(media_id))
            .to_return(status: 200, body: { url: 'https://media.invalid/unavailable.png' }.to_json,
                       headers: { 'Content-Type' => 'application/json' })
          allow(Down).to receive(:download).with('https://media.invalid/unavailable.png', headers: anything)
                                           .and_raise(IOError, 'synthetic external download failure')
          stored = event
          raw = stored.payload.deep_dup
          12.times do
            travel_to(stored.reload.next_attempt_at)
            Whatsapp::ProcessUnifiedEventJob.perform_now(stored.id)
          end

          expect(Down).to have_received(:download).at_least(:once)
          expect(stored.reload).to have_attributes(state: 'review', attempts: 12, next_attempt_at: nil, payload: raw)
          expect(account.messages.where(message_type: %i[incoming outgoing])).to be_empty
          expect(account.contacts.pluck(:id)).to eq([contact.id])
          expect { Whatsapp::ProcessUnifiedEventJob.perform_now(stored.id) }.not_to(change { stored.reload.attempts })
        end
      end
    end
  end
end
