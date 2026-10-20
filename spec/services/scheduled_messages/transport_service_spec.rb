require 'rails_helper'
require 'stringio'
require 'tmpdir'

# Persist the complete scheduler/MessageBuilder path; mock only provider IO.
# rubocop:disable RSpec/AnyInstance, RSpec/MultipleMemoizedHelpers
RSpec.describe ScheduledMessages::TransportService do
  invalid_transports = [{ provider: 'unoapi' }, 'unknown', ''].freeze
  media_types = %w[image/png audio/ogg application/pdf].freeze
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :administrator) }
  let(:suffix) { SecureRandom.random_number(10**7).to_s.rjust(7, '0') }
  let(:uno) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: "+556599#{suffix}",
                              sync_templates: false, validate_provider_config: false)
  end
  let(:meta) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: "+55659#{suffix}",
                              sync_templates: false, validate_provider_config: false)
  end
  let(:channels) { { 'unoapi' => uno, 'whatsapp_cloud' => meta } }
  let(:contact) { create(:contact, account: account, phone_number: '+5565987654321', name: 'Preserved scheduler contact') }
  let!(:uno_alias) { create(:contact_inbox, contact: contact, inbox: uno.inbox, source_id: '5565987654321') }
  let!(:meta_alias) { create(:contact_inbox, contact: contact, inbox: meta.inbox, source_id: '556587654321') }
  let(:origin_provider) { 'unoapi' }
  let(:origin) { channels.fetch(origin_provider) }
  let(:conversation) do
    create(:conversation, account: account, inbox: origin.inbox, contact: contact,
                          contact_inbox: origin_provider == 'unoapi' ? uno_alias : meta_alias)
  end
  let(:schedule) do
    ScheduledMessage.create!(account: account, conversation: conversation, inbox: origin.inbox, contact: contact,
                             label: create(:label, account: account), created_by: agent, sender: agent,
                             scheduled_at: 1.hour.from_now, content: 'Synthetic scheduled content')
  end
  let!(:item) { schedule.items.create!(position: 0, content: 'Synthetic scheduled content', content_type: 'text') }
  let(:service) { described_class.new(schedule) }

  around do |example|
    previous_network_configuration = WebMock::Config.instance.allow_net_connect
    previous_localhost_configuration = WebMock::Config.instance.allow_localhost
    WebMock.disable_net_connect!(allow_localhost: false)
    if example.metadata[:scheduled_storage]
      Dir.mktmpdir('scheduled-transport-media-spec-') do |directory|
        example.metadata[:scheduled_storage_directory] = directory
        example.run
      end
    else
      example.run
    end
  ensure
    WebMock::Config.instance.allow_net_connect = previous_network_configuration
    WebMock::Config.instance.allow_localhost = previous_localhost_configuration
  end

  prepend_before do
    directory = RSpec.current_example.metadata[:scheduled_storage_directory]
    if directory
      storage = ActiveStorage::Service::DiskService.new(root: directory)
      storage.name = ActiveStorage::Blob.service.name
      allow(ActiveStorage::Blob).to receive(:service).and_return(storage)
      allow(ActiveStorage::Blob.services).to receive(:fetch).and_return(storage)
    end
  end

  context 'without a link' do
    it 'leaves old inbox behavior and records unchanged' do
      original = schedule.attributes
      service.capture!
      service.validate!
      expect(schedule.reload.attributes).to eq(original)
      expect(item.reload.whatsapp_transport).to eq({})
      expect(service.canonical_inbox.id).to eq(origin.inbox.id)
    end

    it 'does not accept a selected transport without an authorized pair' do
      expect { service.capture!(requested_provider: 'whatsapp_cloud') }.to raise_error(ArgumentError)
      expect(schedule.reload.whatsapp_transport).to eq({})
    end
  end

  %w[unoapi whatsapp_cloud].each do |principal|
    context "with #{principal} as primary" do
      let!(:link) do
        WhatsappInboxLink.create!(account: account, primary_inbox: channels.fetch(principal).inbox,
                                  secondary_inbox: channels.except(principal).values.sole.inbox,
                                  default_provider: 'whatsapp_cloud', enabled: true)
      end

      %w[unoapi whatsapp_cloud].each do |selected|
        it "persists #{selected} before enqueue and never follows a later default change" do
          service.capture!(requested_provider: selected)
          frozen = schedule.reload.whatsapp_transport.deep_dup
          effective = item.reload.whatsapp_transport.deep_dup
          expect(frozen).to include('requested_provider' => selected, 'link_id' => link.id, 'selection_source' => 'explicit')
          expect(effective).to include('provider' => selected, 'inbox_id' => channels.fetch(selected).inbox.id)
          link.update!(default_provider: selected == 'unoapi' ? 'whatsapp_cloud' : 'unoapi')
          service.capture!
          service.validate!
          expect(schedule.reload.whatsapp_transport).to eq(frozen)
          expect(item.reload.whatsapp_transport).to eq(effective)
        end

        it "dispatches #{selected} to a single primary conversation and preserves operational IDs", :aggregate_failures do
          canonical = if conversation.inbox_id == link.primary_inbox_id
                        conversation
                      else
                        create(:conversation, account: account, inbox: link.primary_inbox, contact: contact,
                                              contact_inbox: principal == 'unoapi' ? uno_alias : meta_alias)
                      end
          service.capture!(requested_provider: selected)
          ScheduledMessages::DeliveryService.new(schedule).perform
          expect(schedule.reload.target_conversation_id).to eq(canonical.id)
          ScheduledMessages::SequenceItemService.new(schedule, 0).perform
          outgoing = item.reload.message
          expect(outgoing.inbox_id).to eq(link.primary_inbox_id)
          expect(outgoing.content_attributes.dig('whatsapp_transport', 'provider')).to eq(selected)
          create(:message, account: account, inbox: meta.inbox, conversation: canonical, sender: contact, message_type: :incoming)
          external_id = selected == 'unoapi' ? 'public-uuid-kept' : 'wamid.public-kept'
          expect_any_instance_of(Channel::Whatsapp).to receive(:send_message) do |channel, _recipient, sent_message|
            expect(channel.id).to eq(channels.fetch(selected).id)
            expect(sent_message.id).to eq(outgoing.id)
            external_id
          end.once
          Whatsapp::SendOnWhatsappService.new(message: outgoing).perform
          expect(outgoing.reload.source_id).to eq(external_id)
          expect(contact.reload.name).to eq('Preserved scheduler contact')
          expect(item.reload.message_id).to eq(outgoing.id)
          ScheduledMessages::DeliveryStatusService.new(outgoing).sent
          expect(schedule.reload).to be_sent
          original_ids = account.messages.outgoing.pluck(:id)
          2.times { ScheduledMessages::SequenceItemService.new(schedule, 0).perform }
          expect(account.messages.outgoing.pluck(:id)).to eq(original_ids)
        end
      end

      it 'pins a legacy client to its original inbox rather than the linked default' do
        service.capture!
        expect(schedule.reload.whatsapp_transport).to include('requested_provider' => origin_provider, 'selection_source' => 'legacy_inbox')
        expect(item.reload.whatsapp_transport['provider']).to eq(origin_provider)
      end

      it 'captures already-existing schedules before any conversation or assignment mutation' do
        expect(schedule.whatsapp_transport).to eq({})
        travel_to(schedule.scheduled_at + 1.minute)
        ScheduledMessages::DeliveryService.new(schedule).perform
        expect(schedule.reload.whatsapp_transport).to include('requested_provider' => origin_provider, 'selection_source' => 'legacy_inbox')
        expect(schedule.target_conversation.inbox_id).to eq(link.primary_inbox_id)
      end

      it 'blocks a disabled link before reopening or creating a conversation' do
        service.capture!(requested_provider: 'unoapi')
        conversation.resolved!
        original = conversation.reload.attributes
        count = account.conversations.count
        link.update!(enabled: false)
        clear_enqueued_jobs
        expect { ScheduledMessages::DeliveryService.new(schedule).perform }.to raise_error(ArgumentError)
        expect(schedule.reload).to be_failed
        expect(conversation.reload.attributes).to eq(original)
        expect(account.conversations.count).to eq(count)
        expect(ScheduledMessages::SequenceItemJob).not_to have_been_enqueued
      end

      it 'rejects the old activation even after the same link is reenabled' do
        service.capture!(requested_provider: 'unoapi')
        link.update!(enabled: false)
        travel 1.second
        link.update!(enabled: true)
        expect { service.validate! }.to raise_error(ArgumentError)
        expect(account.messages.outgoing.count).to eq(0)
      end

      it 'permits explicit review of an unattempted schedule after reactivation' do
        service.capture!(requested_provider: 'unoapi')
        old = schedule.whatsapp_transport.fetch('activation_cutoff')
        link.update!(enabled: false)
        travel 1.second
        link.update!(enabled: true)
        service.capture!(requested_provider: 'whatsapp_cloud')
        expect(schedule.reload.whatsapp_transport['activation_cutoff']).not_to eq(old)
        expect(item.reload.whatsapp_transport['provider']).to eq('whatsapp_cloud')
      end

      it 'revalidates access to the primary inbox for the scheduled sender' do
        service.capture!(requested_provider: 'unoapi')
        account.account_users.find_by!(user: agent).update!(role: :agent)
        expect { service.validate! }.to raise_error(ArgumentError)
        expect(account.messages.outgoing.count).to eq(0)
      end

      it 'restores the request context after worker permission checks' do
        original = [Current.user, Current.account, Current.account_user]
        service.capture!(requested_provider: 'unoapi')
        service.validate!
        expect([Current.user, Current.account, Current.account_user]).to eq(original)
      end

      it 'rejects forged top-level transport objects and unknown providers' do
        invalid_transports.each do |invalid|
          expect { service.capture!(requested_provider: invalid) }.to raise_error(ArgumentError)
        end
        expect(schedule.reload.whatsapp_transport).to eq({})
      end

      it 'freezes the effective capability executor separately from the requested provider' do
        item.update!(content_attributes: { view_once: true })
        service.capture!(requested_provider: 'whatsapp_cloud')
        expect(schedule.whatsapp_transport['requested_provider']).to eq('whatsapp_cloud')
        expect(item.reload.whatsapp_transport).to include('provider' => 'unoapi', 'reason' => 'capability_routing')
      end

      it 'does not reselect or replay a sequence with a dispatched or uncertain item' do
        service.capture!(requested_provider: 'unoapi')
        item.update!(status: :dispatching, dispatched_at: Time.current)
        original = item.reload.attributes
        expect { service.capture!(requested_provider: 'whatsapp_cloud') }.to raise_error(ArgumentError)
        expect(item.reload.attributes).to eq(original)
        expect(account.messages.outgoing.count).to eq(0)
      end

      it 'does not dispatch any further item when the binding is invalidated between sequence items' do
        service.capture!(requested_provider: 'unoapi')
        ScheduledMessages::DeliveryService.new(schedule).perform
        link.update!(enabled: false)
        expect { ScheduledMessages::SequenceItemService.new(schedule, 0).perform }.to raise_error(ArgumentError)
        expect(schedule.reload).to be_failed
        expect(item.reload.message_id).to be_nil
        expect(account.messages.outgoing.count).to eq(0)
      end

      it 'honors a closed Meta window without trying ViperConnect' do
        service.capture!(requested_provider: 'whatsapp_cloud')
        ScheduledMessages::DeliveryService.new(schedule).perform
        ScheduledMessages::SequenceItemService.new(schedule, 0).perform
        outgoing = item.reload.message
        expect_any_instance_of(Channel::Whatsapp).not_to receive(:send_message)
        Whatsapp::SendOnWhatsappService.new(message: outgoing).perform
        ScheduledMessages::DeliveryStatusService.new(outgoing).sent
        expect(schedule.reload).to be_failed
        expect(outgoing.reload).to be_failed
        expect(outgoing.source_id).to be_nil
      end

      it 'stops an uncertain provider response without calling it sent or advancing the sequence' do
        schedule.items.create!(position: 1, content: 'Do not send automatically', content_type: 'text')
        service.capture!(requested_provider: 'unoapi')
        ScheduledMessages::DeliveryService.new(schedule).perform
        ScheduledMessages::SequenceItemService.new(schedule, 0).perform
        outgoing = item.reload.message
        expect_any_instance_of(Channel::Whatsapp).to receive(:send_message).once.and_return(nil)
        Whatsapp::SendOnWhatsappService.new(message: outgoing).perform
        clear_enqueued_jobs
        ScheduledMessages::DeliveryStatusService.new(outgoing).sent
        expect(schedule.reload).to be_failed
        expect(item.reload).to be_failed
        expect(schedule.items.find_by!(position: 1)).to be_pending
        expect(ScheduledMessages::SequenceItemJob).not_to have_been_enqueued
        expect(outgoing.reload.content_attributes.dig('whatsapp_transport', 'delivery_state')).to eq('uncertain')
        expect(outgoing.source_id).to be_nil
      end

      it 'never repeats a timed-out external send or falls back to the other channel' do
        service.capture!(requested_provider: 'unoapi')
        ScheduledMessages::DeliveryService.new(schedule).perform
        ScheduledMessages::SequenceItemService.new(schedule, 0).perform
        outgoing = item.reload.message
        calls = []
        allow_any_instance_of(Channel::Whatsapp).to receive(:send_message) do |channel, *_args|
          calls << channel.id
          raise Net::ReadTimeout, 'synthetic scheduled timeout'
        end
        expect { SendReplyJob.perform_now(outgoing.id) }.to raise_error(Net::ReadTimeout)
        expect(schedule.reload).to be_failed
        expect { SendReplyJob.perform_now(outgoing.id) }.to raise_error(Whatsapp::UnifiedDeliveryAttemptService::UncertainDelivery)
        expect(calls).to eq([uno.id])
        expect(item.reload.message_id).to eq(outgoing.id)
        expect(outgoing.reload.source_id).to be_nil
      end

      media_types.each do |mime|
        it "keeps the same #{mime} blob and transport through actual MessageBuilder dispatch", :scheduled_storage do
          blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('synthetic bytes'), filename: 'synthetic-scheduled-media',
                                                        content_type: mime, identify: false, metadata: { identified: true })
          item.files.attach(blob)
          service.capture!(requested_provider: 'unoapi')
          original_blob_count = ActiveStorage::Blob.count
          ScheduledMessages::DeliveryService.new(schedule).perform
          ScheduledMessages::SequenceItemService.new(schedule, 0).perform
          outgoing = item.reload.message
          expect(outgoing.attachments.sole.file.blob.id).to eq(blob.id)
          expect(item.files.sole.blob.id).to eq(blob.id)
          expect(ActiveStorage::Blob.count).to eq(original_blob_count)
          expect(outgoing.content_attributes.dig('whatsapp_transport', 'provider')).to eq('unoapi')
        end
      end

      context 'when the schedule originated in Meta' do
        let(:origin_provider) { 'whatsapp_cloud' }

        it 'preserves the original provider for an old app even when default is ViperConnect' do
          link.update!(default_provider: 'unoapi')
          service.capture!
          expect(schedule.reload.whatsapp_transport['requested_provider']).to eq('whatsapp_cloud')
          expect(item.reload.whatsapp_transport['provider']).to eq('whatsapp_cloud')
        end
      end
    end
  end
end
# rubocop:enable RSpec/AnyInstance, RSpec/MultipleMemoizedHelpers
