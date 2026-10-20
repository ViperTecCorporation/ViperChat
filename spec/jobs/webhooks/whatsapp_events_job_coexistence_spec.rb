require 'rails_helper'

RSpec.describe Webhooks::WhatsappEventsJob do
  let(:account) { create(:account) }
  let!(:unoapi) do
    create(:channel_whatsapp, account: account, provider: 'unoapi', phone_number: '+5581988985300',
                              provider_config: { 'phone_number_id' => 'uno-business' },
                              sync_templates: false, validate_provider_config: false)
  end
  let!(:meta) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: unoapi.phone_number,
                              sync_templates: false, validate_provider_config: false)
  end
  let(:params) do
    {
      object: 'whatsapp_business_account', phone_number: meta.phone_number,
      entry: [{ changes: [{ field: 'messages', value: { metadata: {
        display_phone_number: '558188985300', phone_number_id: meta.provider_config['phone_number_id']
      } } }] }]
    }
  end

  it 'selects Meta by its provider ID rather than the older ViperConnect row' do
    service = instance_double(Whatsapp::IncomingMessageWhatsappCloudService, perform: true)
    expect(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).with(inbox: meta.inbox, params: params).and_return(service)
    expect(Whatsapp::IncomingMessageUnoapiService).not_to receive(:new)
    described_class.perform_now(params)
  end

  it 'keeps the authenticated ViperConnect inbox through a queued event' do
    params[:whatsapp_provider] = 'unoapi'
    params[:whatsapp_channel_id] = unoapi.id
    params[:entry].first[:changes].first[:value][:metadata][:phone_number_id] = 'uno-business'
    service = instance_double(Whatsapp::IncomingMessageUnoapiService, perform: true)
    expect(Whatsapp::IncomingMessageUnoapiService).to receive(:new).with(inbox: unoapi.inbox, params: params).and_return(service)
    expect(Whatsapp::IncomingMessageWhatsappCloudService).not_to receive(:new)
    described_class.perform_now(params)
  end

  it 'does not use an eight-digit alias to fall back to the wrong provider ID' do
    params[:whatsapp_provider] = 'whatsapp_cloud'
    params[:entry].first[:changes].first[:value][:metadata][:phone_number_id] = 'uno-business'
    expect(Whatsapp::IncomingMessageUnoapiService).not_to receive(:new)
    expect(Whatsapp::IncomingMessageWhatsappCloudService).not_to receive(:new)
    described_class.perform_now(params)
  end

  it 'retains server-side routing evidence when splitting message batches' do
    params[:whatsapp_provider] = 'unoapi'
    params[:whatsapp_channel_id] = unoapi.id
    value = params[:entry].first[:changes].first[:value]
    value[:messages] = [{ id: 'synthetic-one', from: '5581999999999' }, { id: 'synthetic-two', from: '5581888888888' }]
    units = Whatsapp::WebhookEnvelope.units(params)
    expect(units.size).to eq(2)
    expect(units).to all(include(whatsapp_provider: 'unoapi', whatsapp_channel_id: unoapi.id))
    expect(units.map { |unit| unit.dig(:entry, 0, :changes, 0, :value, :messages, 0, :id) }).to eq(%w[synthetic-one synthetic-two])
  end

  it 'does not dispatch authenticated ViperConnect events to Meta account management' do
    params[:whatsapp_provider] = 'unoapi'
    params[:entry].first[:changes].first[:field] = 'account_alerts'
    expect(Whatsapp::ManagementWebhookService).not_to receive(:new)
    expect(described_class.new.send(:dispatch_management, params.with_indifferent_access)).to be(false)
  end
end
