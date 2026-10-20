require 'rails_helper'

RSpec.describe Whatsapp::ReconcileUnifiedMediaJob do
  let(:account) { create(:account) }
  let(:uno) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: '+5565987654321',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:meta) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+556587654321',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:link) do
    WhatsappInboxLink.create!(account: account, primary_inbox: uno.inbox, secondary_inbox: meta.inbox,
                              default_provider: 'unoapi', enabled: true)
  end
  let(:conversation) { create(:conversation, account: account, inbox: uno.inbox) }
  let(:message) { create(:message, account: account, inbox: uno.inbox, conversation: conversation) }
  let!(:record) do
    WhatsappUnifiedMessage.create!(whatsapp_inbox_link: link, message: message, original_id: 'media-job-original',
                                   direction: 'incoming', participant_key: '5565987654321', message_kind: 'image', state: 'ready')
  end
  let(:reconciliation) { instance_double(Whatsapp::UnifiedMediaReconciliationService) }

  before do
    allow(Whatsapp::UnifiedMediaReconciliationService).to receive(:new).with(record: record).and_return(reconciliation)
    clear_enqueued_jobs
  end

  %i[review rejected].each do |status|
    it "persists #{status} diagnostics for administrative review without retrying" do
      result = Whatsapp::UnifiedMediaReconciliationService::Result.new(
        status: status, reason: 'untrusted_mapping', message_ids: [], attachment_ids: []
      )
      allow(reconciliation).to receive(:perform).and_return(result)
      described_class.perform_now(record.id)
      expect(record.reload).to have_attributes(media_review_status: status.to_s, media_review_reason: 'untrusted_mapping')
      expect(enqueued_jobs).to be_empty
      expect(Message.exists?(message.id)).to be(true)
    end
  end

  it 'persists pending evidence and schedules a bounded retry' do
    allow(reconciliation).to receive(:perform).and_return(
      Whatsapp::UnifiedMediaReconciliationService::Result.new(status: :pending, reason: 'primary_media_pending', message_ids: [])
    )
    expect do
      described_class.perform_now(record.id)
    end.to have_enqueued_job(described_class).with(record.id, 1)
    expect(record.reload).to have_attributes(media_review_status: 'pending', media_review_reason: 'primary_media_pending')
  end

  it 'retains pending diagnostics when the retry budget has been exhausted' do
    allow(reconciliation).to receive(:perform).and_return(
      Whatsapp::UnifiedMediaReconciliationService::Result.new(status: :pending, reason: 'primary_media_pending', message_ids: [])
    )
    described_class.perform_now(record.id, 5)
    expect(record.reload.media_review_status).to eq('pending')
    expect(enqueued_jobs).to be_empty
  end

  it 'replaces prior review diagnostics after successful reconciliation' do
    record.update!(media_review_status: 'review', media_review_reason: 'untrusted_mapping')
    allow(reconciliation).to receive(:perform).and_return(
      Whatsapp::UnifiedMediaReconciliationService::Result.new(status: :reconciled, reason: 'primary_media_preserved', message_ids: [])
    )
    described_class.perform_now(record.id)
    expect(record.reload).to have_attributes(media_review_status: 'reconciled', media_review_reason: 'primary_media_preserved')
    expect(enqueued_jobs).to be_empty
  end
end
