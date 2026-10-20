require 'rails_helper'

# The scheduler validates the original transport snapshot before the policy is
# applied at dispatch. Only provider HTTP is fake; all services remain real.
# rubocop:disable RSpec/MultipleMemoizedHelpers, RSpec/SpecFilePathFormat
RSpec.describe ScheduledMessages::TransportService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :administrator) }
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

  %w[unoapi whatsapp_cloud].each do |principal|
    context "with #{principal} as principal" do
      let!(:link) do
        WhatsappInboxLink.create!(account: account, primary_inbox: channels.fetch(principal).inbox,
                                  secondary_inbox: channels.except(principal).values.sole.inbox,
                                  default_provider: 'unoapi', enabled: true,
                                  meta_initial_messages_enabled: true, meta_initial_messages_limit: 2)
      end
      let(:transport) { described_class.new(schedule) }
      let(:public_outgoing) { account.messages.outgoing.where(private: false) }
      let(:conversation) do
        create(:conversation, account: account, inbox: link.primary_inbox, contact: contact,
                              contact_inbox: principal == 'unoapi' ? uno_alias : meta_alias).reload
      end
      let(:schedule) do
        ScheduledMessage.create!(account: account, conversation: conversation, inbox: conversation.inbox, contact: contact,
                                 label: create(:label, account: account), created_by: agent, sender: agent,
                                 scheduled_at: 1.hour.from_now, content: 'Synthetic scheduled policy reply')
      end
      let!(:item) { schedule.items.create!(position: 0, content: schedule.content, content_type: 'text') }

      before do
        create(:message, account: account, inbox: meta.inbox, conversation: conversation, sender: contact,
                         message_type: :incoming, source_id: "wamid.scheduled-incoming-#{SecureRandom.uuid}")
      end

      # The first delivery and its replay share the same claims and provider spies.
      it 'sends the Uno selection through Meta once, preserving intent on retries', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        meta_request = stub_request(:post, meta.provider_service.send(:messages_path))
                       .with { |request| JSON.parse(request.body)['to'] == meta_alias.source_id }
                       .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                                  body: { messages: [{ id: 'wamid.scheduled-policy-reply' }] }.to_json)
        uno_request = stub_request(:post, uno.provider_service.send(:messages_path))
                      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                                 body: { messages: [{ id: SecureRandom.uuid }] }.to_json)
        transport.capture!(requested_provider: 'unoapi')
        selection = schedule.reload.whatsapp_transport.deep_dup
        executor = item.reload.whatsapp_transport.deep_dup
        expect(selection).to include('requested_provider' => 'unoapi', 'selection_source' => 'explicit')
        expect(executor).to include('requested_provider' => 'unoapi', 'provider' => 'unoapi', 'inbox_id' => uno.inbox.id)

        expect { ScheduledMessages::DeliveryService.new(schedule).perform }.not_to(change(public_outgoing, :count))
        expect(schedule.reload.target_conversation_id).to eq(conversation.id)
        expect { ScheduledMessages::SequenceItemService.new(schedule, 0).perform }.to change(public_outgoing, :count).by(1)

        outgoing = item.reload.message
        expect(outgoing).to be_outgoing
        expect(outgoing).not_to be_private
        expect(outgoing.sender).to eq(agent)
        expect(outgoing.conversation_id).to eq(conversation.id)
        expect(outgoing.inbox_id).to eq(link.primary_inbox_id)
        expect(schedule.reload.message_id).to eq(outgoing.id)
        expect(outgoing.content_attributes.fetch('whatsapp_initial_meta_policy')).to include(
          'cycle' => conversation.web_attendance_cycle, 'limit' => 2
        )
        expect(outgoing.content_attributes.fetch('whatsapp_transport')).to eq(executor)
        expect(item.whatsapp_transport).to eq(executor)
        expect { transport.validate_message!(item, outgoing) }.not_to raise_error
        expect(meta_request).not_to have_been_requested
        expect(uno_request).not_to have_been_requested

        expect { Whatsapp::SendOnWhatsappService.new(message: outgoing).perform }.not_to(change(public_outgoing, :count))

        expect(outgoing.reload.source_id).to eq('wamid.scheduled-policy-reply')
        expect(outgoing.content_attributes.dig('whatsapp_initial_meta_policy', 'decision')).to eq('applied')
        expect(outgoing.content_attributes.fetch('whatsapp_transport')).to include(
          'provider' => 'whatsapp_cloud', 'inbox_id' => meta.inbox.id, 'requested_provider' => 'unoapi',
          'reason' => 'initial_meta_messages', 'delivery_state' => 'acknowledged'
        )
        expect(item.reload.whatsapp_transport).to include(
          'provider' => 'whatsapp_cloud', 'inbox_id' => meta.inbox.id,
          'requested_provider' => 'unoapi', 'reason' => 'initial_meta_messages'
        )
        expect(schedule.reload.whatsapp_transport).to eq(selection)
        expect(item.message_id).to eq(outgoing.id)
        expect(meta_request).to have_been_requested.once
        expect(uno_request).not_to have_been_requested

        2.times do
          ScheduledMessages::DeliveryService.new(schedule.reload).perform
          ScheduledMessages::SequenceItemService.new(schedule.reload, 0).perform
          Whatsapp::SendOnWhatsappService.new(message: outgoing.reload).perform
        end

        expect(public_outgoing.pluck(:id)).to eq([outgoing.id])
        expect(schedule.reload.items.pluck(:id, :message_id)).to eq([[item.id, outgoing.id]])
        expect(WhatsappMetaCycleSlot.where(message_id: outgoing.id).count).to eq(1)
        expect(item.reload.whatsapp_transport).to include('provider' => 'whatsapp_cloud', 'requested_provider' => 'unoapi')
        expect(schedule.reload.whatsapp_transport).to eq(selection)
        expect(meta_request).to have_been_requested.once
        expect(uno_request).not_to have_been_requested
      end
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers, RSpec/SpecFilePathFormat
