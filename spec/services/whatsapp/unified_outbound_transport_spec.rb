require 'rails_helper'

# The real dispatcher reloads channels. Instrument that external-send boundary
# rather than replacing the router/send service under test.
# File name is fixed by the integration-test ownership contract.
# rubocop:disable RSpec/AnyInstance, RSpec/MultipleMemoizedHelpers, RSpec/SpecFilePathFormat
RSpec.describe Whatsapp::UnifiedTransportService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:suffix) { SecureRandom.random_number(10**7).to_s.rjust(7, '0') }
  let(:meta) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: "+55659#{suffix}",
                              sync_templates: false, validate_provider_config: false)
  end
  let(:uno) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: "+556599#{suffix}",
                              provider_config: { 'api_key' => 'synthetic', 'url' => 'https://uno.invalid', 'phone_number_id' => 'synthetic' },
                              sync_templates: false, validate_provider_config: false)
  end
  let(:contact) { create(:contact, account: account, phone_number: '+5565987654321') }
  let!(:meta_alias) { create(:contact_inbox, inbox: meta.inbox, contact: contact, source_id: '556587654321') }
  let!(:uno_alias) { create(:contact_inbox, inbox: uno.inbox, contact: contact, source_id: '5565987654321') }
  let(:channels) { { 'unoapi' => uno, 'whatsapp_cloud' => meta } }

  around do |example|
    previous_network_configuration = WebMock::Config.instance.allow_net_connect
    previous_localhost_configuration = WebMock::Config.instance.allow_localhost
    WebMock.disable_net_connect!(allow_localhost: false)
    example.run
  ensure
    WebMock::Config.instance.allow_net_connect = previous_network_configuration
    WebMock::Config.instance.allow_localhost = previous_localhost_configuration
  end

  %w[unoapi whatsapp_cloud].each do |primary_provider|
    context "with #{primary_provider} as principal" do
      let!(:link) do
        WhatsappInboxLink.create!(account: account, primary_inbox: channels.fetch(primary_provider).inbox,
                                  secondary_inbox: channels.fetch(primary_provider == 'unoapi' ? 'whatsapp_cloud' : 'unoapi').inbox,
                                  default_provider: 'whatsapp_cloud', enabled: true)
      end
      let(:conversation) do
        create(:conversation, account: account, inbox: link.primary_inbox, contact: contact,
                              contact_inbox: primary_provider == 'unoapi' ? uno_alias : meta_alias)
      end

      %w[unoapi whatsapp_cloud].each do |selected_provider|
        context "with #{selected_provider} selected at the top level" do
          let(:params) do
            ActionController::Parameters.new(content: 'Envio sintético', message_type: 'outgoing',
                                             whatsapp_transport: selected_provider)
          end
          let(:message) { Messages::MessageBuilder.new(agent, conversation, params).perform }
          let(:effective) { channels.fetch(selected_provider) }
          let(:partner) { channels.fetch(selected_provider == 'unoapi' ? 'whatsapp_cloud' : 'unoapi') }
          let(:external_id) do
            provider = selected_provider == 'unoapi' ? 'uno' : 'meta'
            payload = JSON.parse(Rails.root.join('spec/fixtures/whatsapp_coexistence', "#{provider}_phone_echo.json").read)
            payload.dig('entry', 0, 'changes', 0, 'value', 'message_echoes', 0, 'id')
          end

          it 'persists requested and effective transport before enqueue without changing the primary/default' do
            expect(message.reload.content_attributes['whatsapp_transport']).to include(
              'link_id' => link.id, 'requested_provider' => selected_provider, 'provider' => selected_provider,
              'inbox_id' => effective.inbox.id, 'capability' => 'text', 'reason' => 'selected'
            )
            expect(message.inbox_id).to eq(link.primary_inbox_id)
            expect(link.reload.default_provider).to eq('whatsapp_cloud')
            expect(described_class.new(message: message).recipient)
              .to eq(selected_provider == 'unoapi' ? uno_alias.source_id : meta_alias.source_id)
          end

          it 'sends once via the effective channel and retains its public ID, not the correlation original' do
            outgoing = message
            # Open the official reply window; never stub the router or send service.
            create(:message, account: account, inbox: meta.inbox, conversation: conversation,
                             sender: contact, message_type: :incoming)
            expect_any_instance_of(Channel::Whatsapp).to receive(:send_message) do |channel, recipient, sent_message|
              expect(channel.id).to eq(effective.id)
              expect(recipient).to eq(selected_provider == 'unoapi' ? uno_alias.source_id : meta_alias.source_id)
              expect(sent_message.id).to eq(outgoing.id)
              external_id
            end.once

            Whatsapp::SendOnWhatsappService.new(message: outgoing).perform

            expect(outgoing.reload.source_id).to eq(external_id)
            expect(outgoing.source_id).not_to eq('3EB0ABC1237785D6ED0F2A')
          end

          it 'does not fall back to the partner after a timeout or silently change transport metadata' do
            outgoing = message
            create(:message, account: account, inbox: meta.inbox, conversation: conversation,
                             sender: contact, message_type: :incoming)
            attempts = []
            allow_any_instance_of(Channel::Whatsapp).to receive(:send_message) do |channel, *_args|
              attempts << channel.id
              raise Net::ReadTimeout, 'synthetic uncertain delivery'
            end
            original_metadata = outgoing.content_attributes['whatsapp_transport'].deep_dup

            expect { Whatsapp::SendOnWhatsappService.new(message: outgoing).perform }.to raise_error(Net::ReadTimeout)

            expect(attempts).to eq([effective.id])
            expect(attempts).not_to include(partner.id)
            expect(outgoing.reload.source_id).to be_blank
            expect(outgoing.content_attributes['whatsapp_transport']).to include(original_metadata)
            expect(outgoing.content_attributes.dig('whatsapp_transport', 'delivery_state')).to eq('uncertain')
            expect { Whatsapp::SendOnWhatsappService.new(message: outgoing.reload).perform }
              .to raise_error(Whatsapp::UnifiedDeliveryAttemptService::UncertainDelivery)
            expect(attempts).to eq([effective.id])
          end

          it 'fails closed when the link is disabled after preparation, without trying either provider' do
            outgoing = message
            link.update!(enabled: false)
            expect_any_instance_of(Channel::Whatsapp).not_to receive(:send_message)
            expect { Whatsapp::SendOnWhatsappService.new(message: outgoing).perform }
              .to raise_error(ArgumentError, /link changed/)
            expect(outgoing.reload.source_id).to be_blank
          end

          %w[legacy unavailable].each do |reference_kind|
            it "sends a #{reference_kind} quote once, dropping only an unavailable provider reference" do
              source = if reference_kind == 'unavailable'
                         'unavailable-public-reference'
                       elsif primary_provider == 'unoapi'
                         '43574000-c9ae-11f1-8b89-01afaf97c044'
                       else
                         'wamid.legacy-public-reference'
                       end
              quoted = create(:message, account: account, inbox: conversation.inbox, conversation: conversation, sender: contact,
                                        message_type: :incoming, source_id: source, created_at: 2.days.ago)
              # A recent real incoming record opens the Meta reply window.
              create(:message, account: account, inbox: meta.inbox, conversation: conversation, sender: contact, message_type: :incoming)
              arguments = params.deep_dup
              arguments[:content_attributes] = { in_reply_to: quoted.id }
              outgoing = Messages::MessageBuilder.new(agent, conversation, arguments).perform
              ids = account.messages.order(:id).pluck(:id, :source_id)
              requests = []
              request = stub_request(:post, effective.provider_service.send(:messages_path)).to_return do |sent|
                requests << JSON.parse(sent.body)
                { status: 200, headers: { 'Content-Type' => 'application/json' }, body: { messages: [{ id: external_id }] }.to_json }
              end

              2.times { Whatsapp::SendOnWhatsappService.new(message: outgoing.reload).perform }

              expected_reference = source if reference_kind == 'legacy' && primary_provider == selected_provider
              expect(request).to have_been_requested.once
              expect(requests.sole['context']).to eq(expected_reference ? { 'message_id' => expected_reference } : nil)
              expect(outgoing.reload.source_id).to eq(external_id)
              expect(outgoing.content_attributes.dig('whatsapp_transport', 'delivery_state')).to eq('acknowledged')
              expect(outgoing.content_attributes['in_reply_to']).to eq(quoted.id)
              expect(outgoing.content_attributes['whatsapp_quote_fallback'].present?).to eq(expected_reference.nil?)
              expect(account.messages.order(:id).pluck(:id)).to eq(ids.map(&:first))
              expect(quoted.reload.source_id).to eq(source)
            end
          end
        end
      end

      it 'resolves quotes to UUID or full wamid on the effective provider, never the original' do
        incoming = create(:message, account: account, inbox: conversation.inbox, conversation: conversation, sender: contact,
                                    source_id: 'legacy-source-kept')
        ledger = WhatsappUnifiedMessage.create!(whatsapp_inbox_link: link, message: incoming,
                                                original_id: '3EB0ABC1237785D6ED0F2A', direction: 'incoming',
                                                participant_key: '5565987654321', message_kind: 'text')
        channels.each do |provider, channel|
          fixture_provider = provider == 'unoapi' ? 'uno' : 'meta'
          payload = JSON.parse(Rails.root.join('spec/fixtures/whatsapp_coexistence', "#{fixture_provider}_phone_incoming.json").read)
          external_id = payload.dig('entry', 0, 'changes', 0, 'value', 'messages', 0, 'id')
          identity = WhatsappMessageIdentity.create!(account: account, inbox: channel.inbox, channel: channel, provider: provider,
                                                     external_id: external_id, provider_message_id: ledger.original_id)
          WhatsappUnifiedMessageAlias.create!(whatsapp_unified_message: ledger, whatsapp_message_identity: identity)
          outgoing = Messages::MessageBuilder.new(agent, conversation,
                                                  ActionController::Parameters.new(content: 'Resposta', whatsapp_transport: provider)).perform

          expect(described_class.new(message: outgoing).reference_for(incoming)).to eq(external_id)
          expect(incoming.reload.source_id).to eq('legacy-source-kept')
        end
      end

      it 'requires an explicit available quote alias instead of substituting the other provider ID' do
        incoming = create(:message, account: account, inbox: conversation.inbox, conversation: conversation, sender: contact,
                                    source_id: 'legacy-source-kept')
        outgoing = Messages::MessageBuilder.new(agent, conversation,
                                                ActionController::Parameters.new(content: 'Resposta', whatsapp_transport: 'unoapi')).perform
        expect { described_class.new(message: outgoing).reference_for(incoming) }
          .to raise_error(ArgumentError, /reference is not available/)
      end

      it 'does not prepare or deliver a private note even with a selected transport' do
        note = Messages::MessageBuilder.new(agent, conversation,
                                            ActionController::Parameters.new(content: 'Nota interna', private: true,
                                                                             whatsapp_transport: 'unoapi')).perform
        expect(note.content_attributes['whatsapp_transport']).to be_blank
        expect_any_instance_of(Channel::Whatsapp).not_to receive(:send_message)
        Whatsapp::SendOnWhatsappService.new(message: note).perform
      end

      it 'leaves web delivery independent of the selected WhatsApp transport' do
        conversation.inbox.update!(web_attendance_enabled: true)
        # Reload the trigger-generated display_id before the real Web reminder
        # service locks the conversation; do not bypass its locking/configuration.
        conversation.reload
        message = Messages::MessageBuilder.new(agent, conversation,
                                               ActionController::Parameters.new(content: 'Web somente', delivery_destination: 'web',
                                                                                whatsapp_transport: 'unoapi')).perform
        expect(message.reload.delivery_destination).to eq('web')
        expect(message.content_attributes['whatsapp_transport']).to be_blank
        expect_any_instance_of(Channel::Whatsapp).not_to receive(:send_message)
        Whatsapp::SendOnWhatsappService.new(message: message).perform
      end
    end
  end
end
# rubocop:enable RSpec/AnyInstance, RSpec/MultipleMemoizedHelpers, RSpec/SpecFilePathFormat
