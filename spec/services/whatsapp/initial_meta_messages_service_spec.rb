require 'rails_helper'

# Exercise the real builder, policy, router and dispatcher; only provider HTTP is fake.
# The principal inbox is deliberately independent of the requested/effective provider.
# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe Whatsapp::InitialMetaMessagesService do
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
  let(:channels) { { 'unoapi' => uno, 'whatsapp_cloud' => meta } }
  let(:contact) { create(:contact, account: account, phone_number: '+5565987654321') }
  let!(:meta_alias) { create(:contact_inbox, inbox: meta.inbox, contact: contact, source_id: '556587654321') }
  let!(:uno_alias) { create(:contact_inbox, inbox: uno.inbox, contact: contact, source_id: '5565987654321') }

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
                                  default_provider: 'unoapi', enabled: true,
                                  meta_initial_messages_enabled: true, meta_initial_messages_limit: 2)
      end
      let(:conversation) do
        create(:conversation, account: account, inbox: link.primary_inbox, contact: contact,
                              contact_inbox: primary_provider == 'unoapi' ? uno_alias : meta_alias).reload
      end
      let(:params) { ActionController::Parameters.new(content: 'Synthetic policy reply', whatsapp_transport: 'unoapi') }
      let(:message) { Messages::MessageBuilder.new(agent, conversation, params).perform }
      let!(:incoming_meta) do
        create(:message, account: account, inbox: meta.inbox, conversation: conversation, sender: contact,
                         message_type: :incoming, source_id: "wamid.policy-incoming-#{SecureRandom.uuid}")
      end
      let(:slots) { WhatsappMetaCycleSlot.where(whatsapp_inbox_link_id: link.id, conversation_id: conversation.id) }
      let(:meta_request) do
        stub_request(:post, meta.provider_service.send(:messages_path)).to_return do
          { status: 200, headers: { 'Content-Type' => 'application/json' },
            body: { messages: [{ id: "wamid.policy-#{SecureRandom.uuid}" }] }.to_json }
        end
      end
      let(:uno_request) do
        stub_request(:post, uno.provider_service.send(:messages_path)).to_return do
          { status: 200, headers: { 'Content-Type' => 'application/json' },
            body: { messages: [{ id: SecureRandom.uuid }] }.to_json }
        end
      end

      describe 'server preparation' do
        it 'snapshots cycle and limit at the root without changing the scheduled transport metadata' do
          expect(message.reload.content_attributes.fetch('whatsapp_initial_meta_policy')).to include(
            'cycle' => conversation.web_attendance_cycle, 'limit' => 2
          )
          expect(message.content_attributes.fetch('whatsapp_transport')).to include(
            'requested_provider' => 'unoapi', 'provider' => 'unoapi', 'inbox_id' => uno.inbox.id, 'reason' => 'selected'
          )
          expect(message.content_attributes.fetch('whatsapp_transport')).not_to have_key('whatsapp_initial_meta_policy')
          expect(slots).to be_empty
        end

        it 'does not opt existing links in and retains their selected provider' do
          link.update!(meta_initial_messages_enabled: false)

          expect(message.content_attributes['whatsapp_initial_meta_policy']).to be_blank
          expect { described_class.new(message: message).perform }.not_to change { slots.count }
          expect(message.reload.content_attributes.dig('whatsapp_transport', 'provider')).to eq('unoapi')
        end

        it 'treats a zero limit as disabled even when the toggle is on' do
          link.update!(meta_initial_messages_limit: 0)

          expect { described_class.new(message: message).perform }.not_to change { slots.count }
          expect(message.reload.content_attributes.dig('whatsapp_transport', 'provider')).to eq('unoapi')
        end

        it 'keeps the prepared limit when the setting changes before dispatch' do
          outgoing = message
          link.update!(meta_initial_messages_limit: 1)
          described_class.new(message: outgoing).perform

          expect(outgoing.reload.content_attributes.dig('whatsapp_initial_meta_policy', 'limit')).to eq(2)
          expect(outgoing.content_attributes.dig('whatsapp_transport', 'provider')).to eq('whatsapp_cloud')
        end
      end

      describe 'allocation and dispatch' do
        before do
          meta_request
          uno_request
        end

        it 'sends the first two eligible replies through Meta and the third through Uno without changing editor selection' do
          replies = Array.new(3) { Messages::MessageBuilder.new(agent, conversation, params).perform }

          replies.each { |reply| Whatsapp::SendOnWhatsappService.new(message: reply).perform }

          expect(replies.map { |reply| reply.reload.content_attributes.dig('whatsapp_transport', 'provider') })
            .to eq(%w[whatsapp_cloud whatsapp_cloud unoapi])
          replies.first(2).each do |reply|
            expect(reply.content_attributes.fetch('whatsapp_transport')).to include(
              'requested_provider' => 'unoapi', 'inbox_id' => meta.inbox.id, 'reason' => 'initial_meta_messages'
            )
            expect(reply.content_attributes.dig('whatsapp_initial_meta_policy', 'decision')).to eq('applied')
          end
          expect(replies.map { |reply| reply.content_attributes.dig('whatsapp_transport', 'requested_provider') }).to all(eq('unoapi'))
          expect(replies.map(&:inbox_id)).to all(eq(link.primary_inbox_id))
          expect(slots.order(:position).pluck(:position, :message_id)).to eq([[1, replies[0].id], [2, replies[1].id]])
          expect(slots.pluck(:account_id).uniq).to eq([account.id])
          expect(slots.pluck(:cycle).uniq).to eq([conversation.web_attendance_cycle])
          expect(slots.first.activation_cutoff).to eq(link.activated_at)
          expect(link.reload.default_provider).to eq('unoapi')
          expect(meta_request).to have_been_requested.twice
          expect(uno_request).to have_been_requested.once
        end

        it 'uses only one slot and one provider request when the same message ID is processed repeatedly' do
          outgoing = message
          2.times { described_class.new(message: Message.find(outgoing.id)).perform }
          2.times { Whatsapp::SendOnWhatsappService.new(message: Message.find(outgoing.id)).perform }

          expect(slots.pluck(:message_id)).to eq([outgoing.id])
          expect(outgoing.reload.content_attributes.dig('whatsapp_transport', 'requested_provider')).to eq('unoapi')
          expect(meta_request).to have_been_requested.once
          expect(uno_request).not_to have_been_requested
        end

        it 'counts an explicitly requested Meta send against the same quota' do
          selected_meta = Messages::MessageBuilder.new(agent, conversation, params.merge(whatsapp_transport: 'whatsapp_cloud')).perform
          replies = [selected_meta, *Array.new(2) { Messages::MessageBuilder.new(agent, conversation, params).perform }]

          replies.each { |reply| Whatsapp::SendOnWhatsappService.new(message: reply).perform }

          expect(replies.map { |reply| reply.reload.content_attributes.dig('whatsapp_transport', 'provider') })
            .to eq(%w[whatsapp_cloud whatsapp_cloud unoapi])
          expect(selected_meta.content_attributes.dig('whatsapp_transport', 'requested_provider')).to eq('whatsapp_cloud')
          expect(slots.order(:position).pluck(:message_id)).to eq(replies.first(2).map(&:id))
          expect(meta_request).to have_been_requested.twice
          expect(uno_request).to have_been_requested.once
        end

        [%w[image png image/png], %w[audio mp3 audio/mpeg], %w[video mp4 video/mp4], %w[file pdf application/pdf]].each do |kind, extension, mime|
          it "routes #{kind} through Meta once without recreating the attachment/blob or changing the sender" do
            outgoing = message
            attachment = outgoing.attachments.build(account: account, file_type: kind)
            attachment.file.attach(io: StringIO.new(File.binread(Rails.root.join("spec/assets/sample.#{extension}"))),
                                   filename: "sample.#{extension}", content_type: mime)
            attachment.save!
            original_blob = attachment.file.blob.id
            original_count = ActiveStorage::Blob.count
            expected_type = kind == 'file' ? 'document' : kind
            request = stub_request(:post, meta.provider_service.send(:messages_path))
                      .with { |sent| JSON.parse(sent.body)['type'] == expected_type }
                      .to_return(status: 200, body: { messages: [{ id: "wamid.policy-#{kind}" }] }.to_json,
                                 headers: { 'Content-Type' => 'application/json' })

            2.times { Whatsapp::SendOnWhatsappService.new(message: outgoing.reload).perform }

            expect(request).to have_been_requested.once
            expect(uno_request).not_to have_been_requested
            expect(outgoing.reload.source_id).to eq("wamid.policy-#{kind}")
            expect(outgoing.sender).to eq(agent)
            expect(outgoing.attachments.pluck(:id)).to eq([attachment.id])
            expect(attachment.reload.file.blob.id).to eq(original_blob)
            expect(ActiveStorage::Blob.count).to eq(original_count)
            expect(slots.pluck(:message_id)).to eq([outgoing.id])
          end
        end

        it 'uses the Meta public alias for a quoted reply when the business rule overrides requested Uno' do
          quoted = create(:message, account: account, inbox: conversation.inbox, conversation: conversation, sender: contact,
                                    message_type: :incoming, source_id: '43574000-c9ae-11f1-8b89-01afaf97c044')
          identity = WhatsappMessageIdentity.create!(account: account, inbox: meta.inbox, channel: meta,
                                                     provider: 'whatsapp_cloud', external_id: 'wamid.policy-quote')
          WhatsappUnifiedMessageAlias.create!(whatsapp_message_identity: identity, message: quoted)
          outgoing = Messages::MessageBuilder.new(agent, conversation, params.merge(content_attributes: { in_reply_to: quoted.id })).perform
          request = stub_request(:post, meta.provider_service.send(:messages_path))
                    .with { |sent| JSON.parse(sent.body)['context'] == { 'message_id' => 'wamid.policy-quote' } }
                    .to_return(status: 200, body: { messages: [{ id: 'wamid.policy-quoted-response' }] }.to_json,
                               headers: { 'Content-Type' => 'application/json' })
          2.times { Whatsapp::SendOnWhatsappService.new(message: outgoing.reload).perform }

          expect(request).to have_been_requested.once
          expect(uno_request).not_to have_been_requested
          expect(quoted.reload.source_id).to eq('43574000-c9ae-11f1-8b89-01afaf97c044')
          expect(outgoing.reload.content_attributes.dig('whatsapp_transport', 'requested_provider')).to eq('unoapi')
        end

        it 'does not fall back or release quota after an uncertain Meta HTTP attempt' do
          outgoing = message
          timeout_request = stub_request(:post, meta.provider_service.send(:messages_path)).to_timeout

          expect { Whatsapp::SendOnWhatsappService.new(message: outgoing).perform }.to raise_error(Net::OpenTimeout)
          expect(outgoing.reload.content_attributes.dig('whatsapp_transport', 'delivery_state')).to eq('uncertain')
          expect(outgoing.content_attributes.dig('whatsapp_transport', 'provider')).to eq('whatsapp_cloud')
          expect(outgoing.source_id).to be_blank
          expect(slots.pluck(:message_id)).to eq([outgoing.id])

          expect { Whatsapp::SendOnWhatsappService.new(message: outgoing.reload).perform }
            .to raise_error(Whatsapp::UnifiedDeliveryAttemptService::UncertainDelivery)
          expect(timeout_request).to have_been_requested.once
          expect(uno_request).not_to have_been_requested
          expect(slots.count).to eq(1)

          remaining = Array.new(2) { Messages::MessageBuilder.new(agent, conversation, params).perform }
          remaining.each { |reply| described_class.new(message: reply).perform }
          expect(remaining.map { |reply| reply.reload.content_attributes.dig('whatsapp_transport', 'provider') })
            .to eq(%w[whatsapp_cloud unoapi])
          expect(slots.count).to eq(2)
        end

        %w[attempting uncertain].each do |state|
          it "does not reroute or reserve a slot for an Uno message with an #{state} delivery attempt" do
            outgoing = message
            attributes = outgoing.content_attributes.deep_dup
            attributes['whatsapp_transport'].merge!(
              'delivery_attempt_id' => SecureRandom.uuid, 'delivery_state' => state,
              'delivery_attempted_at' => Time.current.iso8601(6)
            )
            outgoing.update!(content_attributes: attributes)

            expect { described_class.new(message: outgoing).perform }.not_to change { slots.count }
            expect(outgoing.reload.content_attributes.fetch('whatsapp_transport')).to eq(attributes.fetch('whatsapp_transport'))
            expect(meta_request).not_to have_been_requested
            expect(uno_request).not_to have_been_requested
          end
        end
      end

      describe 'Meta eligibility' do
        it 'does not mistake a fresh Uno incoming message for an open Meta reply window' do
          incoming_meta.update!(created_at: 25.hours.ago)
          create(:message, account: account, inbox: uno.inbox, conversation: conversation, sender: contact, message_type: :incoming)
          meta_request
          uno_request

          Whatsapp::SendOnWhatsappService.new(message: message).perform

          expect(message.reload.content_attributes.dig('whatsapp_transport', 'provider')).to eq('unoapi')
          expect(slots).to be_empty
          expect(meta_request).not_to have_been_requested
          expect(uno_request).to have_been_requested.once

          create(:message, account: account, inbox: meta.inbox, conversation: conversation, sender: contact, message_type: :incoming)
          next_reply = Messages::MessageBuilder.new(agent, conversation, params).perform
          described_class.new(message: next_reply).perform
          expect(next_reply.reload.content_attributes.dig('whatsapp_transport', 'provider')).to eq('whatsapp_cloud')
          expect(slots.pluck(:position)).to eq([1])
        end

        it 'skips an unsupported view-once message without spending quota' do
          outgoing = Messages::MessageBuilder.new(agent, conversation, params.merge(content_attributes: { view_once: true })).perform

          expect { described_class.new(message: outgoing).perform }.not_to change { slots.count }
          expect(outgoing.reload.content_attributes.dig('whatsapp_transport', 'provider')).to eq('unoapi')
          described_class.new(message: message).perform
          expect(slots.pluck(:message_id)).to eq([message.id])
          expect(slots.pluck(:position)).to eq([1])
        end

        it 'skips Meta while its channel needs reauthorization' do
          meta.prompt_reauthorization!

          expect { described_class.new(message: message).perform }.not_to change { slots.count }
          expect(message.reload.content_attributes.dig('whatsapp_transport', 'provider')).to eq('unoapi')
        ensure
          meta.reauthorized!
        end

        it 'does not reserve Meta quota for a recipient with only LID aliases and no phone' do
          meta_alias.update!(source_id: '987654321012345@lid')
          uno_alias.update!(source_id: '123456789012345@lid')
          contact.update!(phone_number: nil)
          conversation.reload

          expect { described_class.new(message: message).perform }.not_to change { slots.count }
          expect(message.reload.content_attributes.dig('whatsapp_transport', 'provider')).to eq('unoapi')
        end
      end

      describe 'excluded messages' do
        [
          ['a private note', { private: true }],
          ['an automation rule response', { content_attributes: { automation_rule_id: 123 } }],
          ['an automated campaign', { additional_attributes: { campaign_id: 123 } }],
          ['an automated web absence reminder', { content_attributes: { web_absence_request_key: 'synthetic-reminder' } }],
          ['a historical import', { historical_import: true, content_attributes: { whatsapp_history_import: true } }],
          ['an incoming message', { message_type: :incoming }]
        ].each do |label, attributes|
          it "does not snapshot or allocate quota for #{label}" do
            excluded = build(:message, account: account, inbox: conversation.inbox, conversation: conversation,
                                       sender: agent, message_type: :outgoing, **attributes)
            Whatsapp::UnifiedTransportService.prepare!(message: excluded, requested_provider: 'unoapi')
            excluded.save!

            expect(excluded.content_attributes['whatsapp_initial_meta_policy']).to be_blank
            expect { described_class.new(message: excluded).perform }.not_to change { slots.count }
            expect(excluded.reload.content_attributes.dig('whatsapp_transport', 'reason')).not_to eq('initial_meta_messages')
          end
        end

        it 'excludes an AgentBot response even when it is public and outgoing' do
          bot = create(:agent_bot)
          outgoing = Messages::MessageBuilder.new(bot, conversation, params).perform

          expect(outgoing.sender).to eq(bot)
          expect(outgoing.content_attributes['whatsapp_initial_meta_policy']).to be_blank
          expect { described_class.new(message: outgoing).perform }.not_to change { slots.count }
        end

        it 'excludes web delivery regardless of the selected WhatsApp provider' do
          conversation.inbox.update!(web_attendance_enabled: true)
          outgoing = Messages::MessageBuilder.new(agent, conversation, params.merge(delivery_destination: 'web')).perform

          expect(outgoing).to be_web_attendance
          expect(outgoing.content_attributes['whatsapp_initial_meta_policy']).to be_blank
          expect(outgoing.content_attributes['whatsapp_transport']).to be_blank
          expect { described_class.new(message: outgoing).perform }.not_to change { slots.count }
        end

        it 'leaves group routing unchanged and does not reserve a direct-chat slot' do
          conversation.update!(group: true, group_source_id: '123456789012345@g.us')

          expect(message.content_attributes['whatsapp_initial_meta_policy']).to be_blank
          expect(message.content_attributes['whatsapp_transport']).to be_blank
          expect { described_class.new(message: message).perform }.not_to change { slots.count }
        end
      end

      describe 'quota boundaries' do
        it 'grants a new quota after resolution and reopening through the existing cycle callback' do
          old_cycle = conversation.web_attendance_cycle
          2.times do
            outgoing = Messages::MessageBuilder.new(agent, conversation, params).perform
            described_class.new(message: outgoing).perform
          end
          conversation.update!(status: :resolved)
          conversation.update!(status: :open)
          expect(conversation.reload.web_attendance_cycle).to eq(old_cycle + 1)

          reopened = Array.new(3) { Messages::MessageBuilder.new(agent, conversation, params).perform }
          reopened.each { |reply| described_class.new(message: reply).perform }

          expect(reopened.map { |reply| reply.reload.content_attributes.dig('whatsapp_transport', 'provider') })
            .to eq(%w[whatsapp_cloud whatsapp_cloud unoapi])
          expect(slots.where(cycle: old_cycle).count).to eq(2)
          expect(slots.where(cycle: old_cycle + 1).order(:position).pluck(:position)).to eq([1, 2])
        end

        it 'does not reroute a queued message whose cycle snapshot became stale' do
          outgoing = message
          snapshot = outgoing.content_attributes.fetch('whatsapp_initial_meta_policy').deep_dup
          conversation.update!(status: :resolved)
          conversation.update!(status: :open)

          expect { described_class.new(message: outgoing.reload).perform }.not_to change { slots.count }
          expect(outgoing.reload.content_attributes.dig('whatsapp_transport', 'provider')).to eq('unoapi')
          expect(outgoing.content_attributes.dig('whatsapp_initial_meta_policy', 'cycle')).to eq(snapshot.fetch('cycle'))
        end

        it 'keeps counters separate for two conversations under the same link and cycle' do
          other_conversation = create(:conversation, account: account, inbox: conversation.inbox, contact: contact,
                                                     contact_inbox: conversation.contact_inbox).reload
          create(:message, account: account, inbox: meta.inbox, conversation: other_conversation, sender: contact, message_type: :incoming)
          2.times do
            outgoing = Messages::MessageBuilder.new(agent, conversation, params).perform
            described_class.new(message: outgoing).perform
          end
          other_reply = Messages::MessageBuilder.new(agent, other_conversation, params).perform
          described_class.new(message: other_reply).perform

          expect(other_conversation.web_attendance_cycle).to eq(conversation.web_attendance_cycle)
          expect(other_reply.reload.content_attributes.dig('whatsapp_transport', 'provider')).to eq('whatsapp_cloud')
          expect(slots.count).to eq(2)
          expect(WhatsappMetaCycleSlot.where(conversation_id: other_conversation.id).pluck(:position)).to eq([1])
        end

        it 'starts a new generation on reactivation without rerouting an old prepared snapshot' do
          described_class.new(message: message).perform
          stale = Messages::MessageBuilder.new(agent, conversation, params).perform
          old_cutoff = link.activated_at
          link.update!(enabled: false)
          travel_to(1.second.from_now) { link.update!(enabled: true) }
          expect(link.reload.activated_at).not_to eq(old_cutoff)
          meta_request
          uno_request

          expect { Whatsapp::SendOnWhatsappService.new(message: stale.reload).perform }.to raise_error(ArgumentError, /link changed/)
          fresh = Messages::MessageBuilder.new(agent, conversation, params).perform
          described_class.new(message: fresh).perform

          expect(fresh.reload.content_attributes.dig('whatsapp_transport', 'provider')).to eq('whatsapp_cloud')
          expect(slots.where(activation_cutoff: old_cutoff).count).to eq(1)
          expect(slots.where(activation_cutoff: link.activated_at).pluck(:position)).to eq([1])
          expect(meta_request).not_to have_been_requested
          expect(uno_request).not_to have_been_requested
        end
      end

      describe 'durable slot constraints' do
        before { described_class.new(message: message).perform }

        it 'enforces one reservation per message at the database boundary' do
          duplicate = slots.sole.dup
          duplicate.position = 2

          expect do
            WhatsappMetaCycleSlot.transaction(requires_new: true) { duplicate.save!(validate: false) }
          end.to raise_error(ActiveRecord::RecordNotUnique)
          expect(slots.count).to eq(1)
        end

        it 'enforces one position per conversation, cycle and link generation at the database boundary' do
          duplicate = slots.sole.dup
          duplicate.message = Messages::MessageBuilder.new(agent, conversation, params).perform

          expect do
            WhatsappMetaCycleSlot.transaction(requires_new: true) { duplicate.save!(validate: false) }
          end.to raise_error(ActiveRecord::RecordNotUnique)
          expect(slots.count).to eq(1)
        end

        it 'retains consumed quota when its message is deleted, nullifying the optional reference' do
          slot = slots.sole
          message.destroy!

          expect(slot.reload.message_id).to be_nil
          expect(slots.count).to eq(1)
          expect(slots.pluck(:position)).to eq([1])
        end
      end
    end
  end

  describe 'link policy settings' do
    it 'defaults old and newly built links to off with a limit of five' do
      expect(WhatsappInboxLink.new).to have_attributes(meta_initial_messages_enabled: false, meta_initial_messages_limit: 5)
    end

    [-1, 1001].each do |limit|
      it "rejects a limit of #{limit}" do
        link = WhatsappInboxLink.new(meta_initial_messages_limit: limit)
        link.valid?

        expect(link.errors[:meta_initial_messages_limit]).to be_present
      end
    end

    [0, 1000].each do |limit|
      it "accepts the boundary limit #{limit}" do
        link = WhatsappInboxLink.new(meta_initial_messages_limit: limit)
        link.valid?

        expect(link.errors[:meta_initial_messages_limit]).to be_empty
      end
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
