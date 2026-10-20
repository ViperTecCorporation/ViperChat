require 'rails_helper'

RSpec.describe Webhooks::WhatsappEventsJob do # rubocop:disable RSpec/SpecFilePathFormat
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }

  (Whatsapp::WebhookFields::ADMIN + Whatsapp::WebhookFields::GROUP).each do |field|
    it "routes #{field} to a durable receipt, never a live message or a contact" do
      body = { object: 'whatsapp_business_account', phone_number: channel.phone_number, entry: [
        { id: channel.provider_config['business_account_id'], changes: [{ field: field, value: { status: 'ACTIVE' } }] }
      ] }
      expect do
        described_class.perform_now(body)
      end.to change(WhatsappManagementEvent, :count).by(1)
      expect(channel.account.messages).to be_empty
      expect(channel.account.contacts).to be_empty
      expect(WhatsappManagementEvent.last.field).to eq(field)
    end
  end

  it 'queues independent batch changes so one pending item cannot block the other events' do
    body = { object: 'whatsapp_business_account', phone_number: channel.phone_number, entry: [
      { id: channel.provider_config['business_account_id'], changes: [
        { field: 'history', value: { history: [] } }, { field: 'security', value: { status: 'ACTIVE' } }
      ] }
    ] }
    expect { described_class.perform_now(body) }.to have_enqueued_job(described_class).exactly(2).times
    expect(WhatsappManagementEvent.count).to eq(0)
    Whatsapp::WebhookEnvelope.units(body).each { |unit| described_class.perform_now(unit) }
    expect(WhatsappManagementEvent.pluck(:field).sort).to eq(%w[history security])
  end

  it 'treats the additional message_echoes field as an outgoing echo' do
    value = { metadata: { phone_number_id: channel.provider_config['phone_number_id'], display_phone_number: channel.phone_number.delete('+') },
              message_echoes: [{ id: 'synthetic-echo', from: channel.phone_number.delete('+'), to: '5511999999999',
                                 type: 'text', text: { body: 'synthetic' } }] }
    body = { object: 'whatsapp_business_account', phone_number: channel.phone_number,
             entry: [{ changes: [{ field: 'message_echoes', value: value }] }] }
    service = instance_double(Whatsapp::IncomingMessageWhatsappCloudService, perform: nil)
    expect(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new)
      .with(inbox: channel.inbox, params: body.with_indifferent_access, outgoing_echo: true).and_return(service)
    described_class.perform_now(body)
    expect(WhatsappManagementEvent.count).to eq(0)
  end

  it 'applies a verified Meta group-settings receipt only once across webhook retries' do
    conversation = create(:conversation, inbox: channel.inbox, account: channel.account,
                                         group: true, group_source_id: '120363040468224', group_title: 'Original')
    body = { phone_number: channel.phone_number, entry: [{ id: channel.provider_config['business_account_id'], changes: [
      { field: 'group_settings_update', value: { group_id: conversation.group_source_id, changes: { subject: 'Updated' } } }
    ] }] }
    expect(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).once.and_call_original
    2.times { described_class.perform_now(body) }
    expect(WhatsappManagementEvent.count).to eq(1)
    expect(WhatsappManagementEvent.last.state).to eq('processed')
    expect(conversation.reload.group_title).to eq('Updated')
  end

  it 'does not apply a group-setting change rejected by the WABA ownership check' do
    body = { phone_number: channel.phone_number, entry: [{ id: 'other-waba', changes: [
      { field: 'group_settings_update', value: { group_id: '120363040468224', changes: { subject: 'Wrong tenant' } } }
    ] }] }
    expect(Whatsapp::IncomingMessageWhatsappCloudService).not_to receive(:new)
    described_class.perform_now(body)
    expect(WhatsappManagementEvent.count).to eq(0)
  end
end
