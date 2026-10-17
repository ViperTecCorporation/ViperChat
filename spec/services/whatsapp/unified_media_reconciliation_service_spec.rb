require 'rails_helper'
require 'base64'
require 'stringio'
require 'tmpdir'

# The matrix deliberately shares the same real persistence/storage setup.
# rubocop:disable RSpec/MultipleMemoizedHelpers, Rails/SkipsModelValidations
RSpec.describe Whatsapp::UnifiedMediaReconciliationService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5565987654321') }
  let(:principal_provider) { 'whatsapp_cloud' }
  let(:direction) { 'incoming' }
  let(:kind) { 'image' }
  let(:mime) { 'image/png' }
  let(:file_type) { 'image' }
  let(:business_suffix) { SecureRandom.random_number(10**7).to_s.rjust(7, '0') }
  let(:original_id) { '3A86A3AC7C1C7BCE3881' }
  let(:storage) do
    ActiveStorage::Service::DiskService.new(root: RSpec.current_example.metadata.fetch(:unified_media_storage_directory)).tap do |service|
      service.name = ActiveStorage::Blob.service.name
    end
  end

  let(:meta_id) do
    marker = direction == 'incoming' ? "\x12" : "\x11"
    envelope = "\x1c\x18\x0d5565987654321\x15\x02\x00#{marker}\x18#{original_id.bytesize.chr}#{original_id}\x00"
    "wamid.#{Base64.strict_encode64(envelope)}"
  end
  let(:channels) do
    %w[whatsapp_cloud unoapi].index_with do |provider|
      business_number = provider == 'whatsapp_cloud' ? "+55658#{business_suffix}" : "+556598#{business_suffix}"
      create(:channel_whatsapp, account: account, provider: provider, phone_number: business_number,
                                sync_templates: false, validate_provider_config: false)
    end
  end
  let!(:link) do
    # Activation is assigned by around_save, not by the caller's activated_at.
    # Create at the real cutoff, then restore the clock before persisting copies.
    travel_to(1.hour.ago) do
      WhatsappInboxLink.create!(account: account, primary_inbox: channels.fetch(principal_provider).inbox,
                                secondary_inbox: channels.except(principal_provider).values.sole.inbox,
                                default_provider: principal_provider, enabled: true)
    end
  end
  let!(:messages) do
    channels.transform_values do |channel|
      conversation = create(:conversation, account: account, inbox: channel.inbox, contact: contact)
      create(:message, account: account, inbox: channel.inbox, conversation: conversation, sender: contact,
                       message_type: direction, source_id: channel.provider == 'unoapi' ? 'legacy-public-uuid' : meta_id)
    end
  end
  let!(:record) do
    WhatsappUnifiedMessage.create!(whatsapp_inbox_link: link, message: messages.fetch(principal_provider),
                                   original_id: original_id, direction: direction, participant_key: '5565987654321',
                                   message_kind: kind, state: 'ready', media_inbox_id: link.primary_inbox_id)
  end
  let!(:identities) do
    channels.map do |provider, channel|
      observations = {
        'business_number' => channel.phone_number, 'direction' => direction, 'message_type' => kind,
        'timestamp' => Time.current.to_i.to_s,
        'participants' => direction == 'incoming' ? { 'from' => '5565987654321' } : { 'to' => '5565987654321' }
      }
      observations['meta_id_adapter'] = { 'status' => 'recognized', 'direction' => direction } if provider == 'whatsapp_cloud'
      identity = WhatsappMessageIdentity.create!(account: account, inbox: channel.inbox, channel: channel,
                                                 provider: provider, external_id: messages.fetch(provider).source_id,
                                                 provider_message_id: original_id, observations: observations)
      identity.message_links.create!(message: messages.fetch(provider))
      # Alias message_id intentionally absent: discovery must traverse message_links.
      record.aliases.create!(whatsapp_message_identity: identity)
      identity
    end
  end
  let!(:attachments) do
    messages.transform_values do |message|
      attachment = Attachment.create!(message: message, account: account, file_type: file_type)
      blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("synthetic #{message.inbox_id} bytes"),
                                                    filename: "sample.#{mime.split('/').last}", content_type: mime, identify: false)
      attachment.file.attach(blob)
      attachment
    end
  end
  let(:service) { described_class.new(record: record) }
  let(:principal) { attachments.fetch(principal_provider) }
  let(:secondary) { attachments.except(principal_provider).values.sole }

  # Run inside the mocks lifecycle, before eager fixtures upload their blobs.
  prepend_before do
    allow(ActiveStorage::Blob).to receive(:service).and_return(storage)
    allow(ActiveStorage::Blob.services).to receive(:fetch).and_return(storage)
  end

  around do |example|
    # Every object is synthetic and isolated from configured/local real uploads.
    Dir.mktmpdir('unified-media-spec-') do |directory|
      example.metadata[:unified_media_storage_directory] = directory
      example.run
    end
  ensure
    example.metadata.delete(:unified_media_storage_directory)
  end

  media_formats = [
    ['image', 'image/png', 'image'], ['audio', 'audio/ogg', 'audio'], ['video', 'video/mp4', 'video'],
    ['sticker', 'image/webp', 'image'], ['document', 'application/pdf', 'file'], ['document', 'application/zip', 'file']
  ]
  %w[whatsapp_cloud unoapi].each do |provider|
    context "with #{provider} as principal" do
      let(:principal_provider) { provider }

      media_formats.each do |media_kind, media_mime, attachment_type|
        context "with #{media_kind}" do
          let(:kind) { media_kind }
          let(:mime) { media_mime }
          let(:file_type) { attachment_type }

          it 'uses principal bytes and preserves every public message, attachment and AS attachment ID' do # rubocop:disable RSpec/MultipleExpectations
            snapshots = messages.values.index_with { |message| message.reload.attributes }
            attachment_ids = attachments.values.map(&:id)
            file_ids = attachments.values.map { |item| item.file.attachment.id }
            winner = principal.file.blob
            old_blob = secondary.file.blob
            expect(old_blob.download).not_to eq(winner.download)

            expect(service.perform.status).to eq(:reconciled)
            expect(secondary.reload.file.blob_id).to eq(winner.id)
            expect(secondary.file.download).to eq(winner.download)
            expect(attachments.values.map { |item| item.reload.file.attachment.id }).to eq(file_ids)
            expect(Attachment.where(id: attachment_ids).count).to eq(2)
            snapshots.each { |message, attributes| expect(message.reload.attributes).to eq(attributes) }
            expect(service.perform.status).to eq(:unchanged)
            expect(record.reload.media_inbox_id).to eq(link.primary_inbox_id)
          end
        end
      end
    end
  end

  context 'with outgoing copies' do
    let(:direction) { 'outgoing' }

    it 'also uses the principal media for a proven echo pair' do
      expect(service.perform.status).to eq(:reconciled)
      expect(secondary.reload.file.blob_id).to eq(principal.file.blob_id)
    end
  end

  it 'keeps secondary media until the principal object exists' do
    old_blob_id = secondary.file.blob_id
    principal.file.blob.service.delete(principal.file.blob.key)
    expect(service.perform.reason).to eq(:principal_unavailable)
    expect(secondary.reload.file.blob_id).to eq(old_blob_id)
  end

  it 'includes the canonical message even when its identity has no persisted message link' do
    identities.find { |identity| identity.inbox_id == link.primary_inbox_id }.message_links.delete_all
    expect(service.perform.status).to eq(:reconciled)
    expect(secondary.reload.file.blob_id).to eq(principal.file.blob_id)
  end

  it 'never purges a secondary blob shared by another AS attachment' do
    old_blob = secondary.file.blob
    unrelated = create(:message, account: account, inbox: link.secondary_inbox, conversation: secondary.message.conversation)
    extra = Attachment.create!(message: unrelated, account: account, file_type: :image)
    extra.file.attach(old_blob)
    expect(service.perform.status).to eq(:reconciled)
    described_class::PurgeAfterCommit.new([old_blob.id]).committed!
    expect(old_blob.reload.download).to start_with('synthetic')
    expect(Whatsapp::PurgeUnifiedMediaBlobJob).not_to have_been_enqueued
  end

  it 'preserves a replaced blob referenced by a sticker even with no AS attachments left' do
    old_blob = secondary.file.blob
    WhatsappSticker.create!(account: account, inbox: link.secondary_inbox, blob: old_blob)
    service.perform
    described_class::PurgeAfterCommit.new([old_blob.id]).committed!
    expect(old_blob.reload.download).to start_with('synthetic')
    expect(Whatsapp::PurgeUnifiedMediaBlobJob).not_to have_been_enqueued
  end

  it 'enqueues only an unreferenced old blob after commit, never the winner' do
    old_blob = secondary.file.blob
    service.perform
    expect { described_class::PurgeAfterCommit.new([old_blob.id, principal.file.blob_id]).committed! }
      .to have_enqueued_job(Whatsapp::PurgeUnifiedMediaBlobJob).with(old_blob.id)
  end

  it 'preserves JSON signed references used by scheduled items' do
    old_blob = secondary.file.blob
    scheduled = create(
      :scheduled_message, account: account, inbox: secondary.message.inbox,
                          conversation: secondary.message.conversation, contact: contact
    )
    scheduled.items.sole.update!(attachment_blob_ids: [old_blob.signed_id])
    service.perform
    expect(old_blob.reload.attachments).to be_empty
    expect { described_class::PurgeAfterCommit.new([old_blob.id]).committed! }.not_to have_enqueued_job(Whatsapp::PurgeUnifiedMediaBlobJob)
    expect(old_blob.download).to start_with('synthetic')
  end

  it 'rechecks new shared attachments added between enqueue and purge execution' do
    old_blob = secondary.file.blob
    service.perform
    unrelated = create(:message, account: account, inbox: link.secondary_inbox, conversation: secondary.message.conversation)
    extra = Attachment.create!(message: unrelated, account: account, file_type: :image)
    extra.file.attach(old_blob)

    Whatsapp::PurgeUnifiedMediaBlobJob.perform_now(old_blob.id)
    expect(old_blob.reload.download).to start_with('synthetic')
    expect(extra.reload.file.blob_id).to eq(old_blob.id)
  end

  it 'rechecks scheduled signed references added after reconciliation' do
    old_blob = secondary.file.blob
    service.perform
    scheduled = create(:scheduled_message, account: account, inbox: secondary.message.inbox,
                                          conversation: secondary.message.conversation, contact: contact)
    scheduled.items.sole.update!(attachment_blob_ids: [old_blob.signed_id])

    Whatsapp::PurgeUnifiedMediaBlobJob.perform_now(old_blob.id)
    expect(old_blob.reload.download).to start_with('synthetic')
  end

  it 'removes only the unreferenced old object and makes purge retries harmless' do
    old_blob = secondary.file.blob
    old_key = old_blob.key
    service.perform

    2.times { Whatsapp::PurgeUnifiedMediaBlobJob.perform_now(old_blob.id) }
    expect(ActiveStorage::Blob.exists?(old_blob.id)).to be(false)
    expect(storage.exist?(old_key)).to be(false)
    expect(principal.reload.file.download).to start_with('synthetic')
    expect(secondary.reload.file.blob_id).to eq(principal.file.blob_id)
  end

  it 'refreshes existing bubbles after repair without creating messages or broadcasting another creation' do
    dispatcher = Rails.configuration.dispatcher
    allow(dispatcher).to receive(:dispatch)
    ids = messages.values.map(&:id).sort

    expect { Whatsapp::ReconcileUnifiedMediaJob.perform_now(record.id) }.not_to change(Message, :count)
    expect(secondary.reload.file.blob_id).to eq(principal.file.blob_id)
    messages.each_value do |message|
      expect(dispatcher).to have_received(:dispatch).with(Events::Types::MESSAGE_UPDATED, anything,
                                                         hash_including(message: having_attributes(id: message.id)))
    end
    expect(dispatcher).not_to have_received(:dispatch).with(Events::Types::MESSAGE_CREATED, anything, anything)
    expect(Message.where(id: ids).order(:id).pluck(:id)).to eq(ids)
  end

  it 'retries a temporarily missing principal object with a bounded budget' do
    allow(storage).to receive(:exist?).and_call_original
    allow(storage).to receive(:exist?).with(principal.file.blob.key).and_return(false)
    expect { Whatsapp::ReconcileUnifiedMediaJob.perform_now(record.id) }
      .to have_enqueued_job(Whatsapp::ReconcileUnifiedMediaJob).with(record.id, 1).at(a_value_within(2.seconds).of(30.seconds.from_now))
    clear_enqueued_jobs
    expect { Whatsapp::ReconcileUnifiedMediaJob.perform_now(record.id, 5) }
      .not_to have_enqueued_job(Whatsapp::ReconcileUnifiedMediaJob)
    expect(secondary.reload.file.blob_id).not_to eq(principal.file.blob_id)
  end

  it 'does not enqueue a purge when the caller rolls back the outer transaction' do
    old_blob_id = secondary.file.blob_id
    expect do
      ActiveRecord::Base.transaction(requires_new: true) do
        expect(service.perform.status).to eq(:reconciled)
        raise ActiveRecord::Rollback
      end
    end.not_to have_enqueued_job(Whatsapp::PurgeUnifiedMediaBlobJob)
    expect(secondary.reload.file.blob_id).to eq(old_blob_id)
  end

  it 'rolls back blob substitution if ledger persistence fails' do
    old_blob_id = secondary.file.blob_id
    record.update!(media_inbox_id: nil)
    allow(record).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(record))
    expect { service.perform }.to raise_error(ActiveRecord::RecordInvalid)
    expect(secondary.reload.file.blob_id).to eq(old_blob_id)
    expect(Whatsapp::PurgeUnifiedMediaBlobJob).not_to have_been_enqueued
  end

  {
    disabled: -> { link.update!(enabled: false) },
    conflict: -> { identities.first.update!(observations: identities.first.observations.merge('conflicting_provider_message_ids' => ['other'])) },
    cutoff: -> { identities.first.update!(observations: identities.first.observations.merge('timestamp' => 2.hours.ago.to_i.to_s)) },
    untrusted: -> { identities.find { |identity| identity.provider == 'whatsapp_cloud' }.update!(external_id: 'wamid.unrecognized') },
    account: -> { messages.values.last.update_column(:account_id, create(:account).id) },
    contact: -> { messages.values.last.conversation.update!(contact: create(:contact, account: account)) },
    direction: -> { messages.values.last.update_column(:message_type, Message.message_types.fetch('outgoing')) },
    private: -> { messages.values.last.update_column(:private, true) },
    historical: -> { messages.values.last.update_column(:created_at, 2.days.ago) },
    mismatch: -> { secondary.file.blob.update!(content_type: 'audio/ogg') },
    multiple: -> { Attachment.create!(message: secondary.message, account: account, file_type: :image) }
  }.each do |scenario, mutation|
    it "rejects #{scenario} without changing or purging media" do
      instance_exec(&mutation)
      before = ActiveStorage::Attachment.order(:id).pluck(:id, :blob_id)
      expect(service.perform.status).to be_in(%i[review rejected])
      expect(ActiveStorage::Attachment.order(:id).pluck(:id, :blob_id)).to eq(before)
      expect(Whatsapp::PurgeUnifiedMediaBlobJob).not_to have_been_enqueued
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers, Rails/SkipsModelValidations
