require 'rails_helper'

RSpec.describe Whatsapp::IncomingMessageUnoapiService do
  let(:channel) { create(:channel_whatsapp, provider: 'unoapi', sync_templates: false, validate_provider_config: false) }
  let(:conversation) { create(:conversation, inbox: channel.inbox, account: channel.inbox.account) }
  let!(:original) { create(:message, conversation: conversation, source_id: 'original') }
  let!(:message) do
    create(:message, conversation: conversation, message_type: :outgoing, source_id: 'uno-warning-id',
                     content_attributes: { in_reply_to_external_id: 'original' })
  end
  let(:warning) { { code: 'REPLY_SENT_WITHOUT_QUOTE', message: 'Sent without quote' } }
  let(:status) { { id: message.source_id, status: 'sent', warnings: [warning] } }
  let(:params) { { entry: [{ changes: [{ value: { statuses: [status] } }] }] }.with_indifferent_access }
  let(:service) { described_class.new(inbox: channel.inbox, params: params) }

  it 'persists a success warning and the original reference without sending again' do
    expect { service.perform }.not_to have_enqueued_job(SendReplyJob)
    expect(message.reload.status).to eq('sent')
    expect(message.content_attributes['unoapi_warnings']).to eq([warning.stringify_keys])
    expect(message.content_attributes['in_reply_to_external_id']).to eq(original.source_id)
    expect(message.external_error).to be_blank
  end

  %w[delivered read].each do |current_status|
    it "persists warnings without regressing #{current_status}" do
      message.update!(status: current_status)
      service.perform
      expect(message.reload.status).to eq(current_status)
      expect(message.content_attributes['unoapi_warnings'].size).to eq(1)
    end
  end

  %w[sent delivered read].each do |incoming_status|
    it "processes warning attached to repeated #{incoming_status}" do
      message.update!(status: incoming_status)
      status[:status] = incoming_status
      service.perform
      expect(message.reload.content_attributes['unoapi_warnings'].size).to eq(1)
    end
  end

  it 'broadcasts the change once and deduplicates subsequent identical callbacks' do
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original
    service.perform
    updated_at = message.reload.updated_at
    service.perform
    expect(message.reload.updated_at).to eq(updated_at)
    expect(message.content_attributes['unoapi_warnings'].size).to eq(1)
    expect(Rails.configuration.dispatcher).to have_received(:dispatch).with('message.updated', anything, anything).once
  end

  it 'retains warnings after a later status without warnings' do
    service.perform
    params[:entry][0][:changes][0][:value][:statuses][0].replace(id: message.source_id, status: 'read')
    described_class.new(inbox: channel.inbox, params: params).perform
    expect(message.reload.status).to eq('read')
    expect(message.content_attributes['unoapi_warnings'].size).to eq(1)
  end

  it 'retries a missing external ID and reconciles after send association' do
    status[:id] = 'pending-id'
    expect { service.perform }.to raise_error(ActiveRecord::RecordNotFound)
    message.update!(source_id: 'pending-id')
    expect { service.perform }.not_to have_enqueued_job(SendReplyJob)
    expect(message.reload.content_attributes['unoapi_warnings'].size).to eq(1)
  end

  it 'never correlates a source ID from another inbox or account' do
    other = create(:channel_whatsapp, provider: 'unoapi', sync_templates: false, validate_provider_config: false)
    expect { described_class.new(inbox: other.inbox, params: params).perform }.to raise_error(ActiveRecord::RecordNotFound)
    expect(message.reload.content_attributes['unoapi_warnings']).to be_nil
  end

  it 'isolates inboxes within the same account too' do
    other = create(:channel_whatsapp, account: channel.account, provider: 'unoapi', sync_templates: false, validate_provider_config: false)
    expect { described_class.new(inbox: other.inbox, params: params).perform }.to raise_error(ActiveRecord::RecordNotFound)
    expect(message.reload.content_attributes['unoapi_warnings']).to be_nil
  end

  it 'schedules the actual webhook for retry until the external ID is associated' do
    params[:phone_number] = channel.phone_number
    params[:entry][0][:changes][0][:value][:metadata] = {
      phone_number_id: channel.provider_config['phone_number_id'], display_phone_number: channel.phone_number.delete('+')
    }
    params[:entry][0][:changes][0][:value][:statuses][0][:id] = 'later'
    expect { Webhooks::WhatsappEventsJob.perform_now(params) }.to have_enqueued_job(Webhooks::WhatsappEventsJob)
    message.update!(source_id: 'later')
    expect { Webhooks::WhatsappEventsJob.perform_now(params) }.not_to have_enqueued_job(SendReplyJob)
    expect(message.reload.content_attributes['unoapi_warnings'].size).to eq(1)
  end

  it 'does not enable UnoAPI warning semantics in the official Meta service' do
    Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: channel.inbox, params: params).perform
    expect(message.reload.content_attributes['unoapi_warnings']).to be_nil
  end

  it 'deduplicates by code even if the warning text changes' do
    service.perform
    params[:entry][0][:changes][0][:value][:statuses][0][:warnings][0][:message] = 'Another language'
    described_class.new(inbox: channel.inbox, params: params).perform
    expect(message.reload.content_attributes['unoapi_warnings']).to eq([warning.stringify_keys])
  end

  it 'processes every status and preserves unknown codes as plain strings' do
    warning.replace(code: 'FUTURE_WARNING', message: '<img src=x onerror=alert(1)>')
    params[:entry][0][:changes][0][:value][:statuses].unshift(id: 'unrelated', status: 'sent')
    service.perform
    expect(message.reload.content_attributes['unoapi_warnings']).to eq([warning.stringify_keys])
  end

  it 'still handles actual failures through the existing error flow' do
    status.merge!(status: 'failed', errors: [{ code: 413, title: 'Too large' }])
    service.perform
    expect(message.reload.status).to eq('failed')
    expect(message.external_error).to eq('413: Too large')
  end
end
