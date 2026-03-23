require 'rails_helper'

describe Whatsapp::IncomingMessageUnoapiService do
  describe '#perform' do
    after do
      Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) }
    end

    let!(:whatsapp_channel) { create(:channel_whatsapp, provider: 'unoapi', sync_templates: false, validate_provider_config: false) }
    let(:source_phone_number) { whatsapp_channel.phone_number.delete('+') }
    let(:customer_phone_number) { '2423423243' }
    let(:base_value) do
      {
        metadata: {
          display_phone_number: source_phone_number,
          phone_number_id: whatsapp_channel.provider_config['phone_number_id']
        },
        contacts: [{ profile: { name: 'Sojan Jose' }, wa_id: customer_phone_number }],
        messages: [{
          from: source_phone_number,
          id: 'wamid.UNOAPI_MESSAGE_ID',
          text: { body: 'Mensagem enviada pelo aparelho' },
          timestamp: '1770407829',
          type: 'text'
        }]
      }
    end
    let(:params) do
      {
        phone_number: whatsapp_channel.phone_number,
        object: 'whatsapp_business_account',
        entry: [{
          changes: [{
            value: base_value
          }]
        }]
      }.with_indifferent_access
    end

    it 'stores a native-app message from the inbox number as outgoing external echo' do
      described_class.new(inbox: whatsapp_channel.inbox, params: params).perform

      message = whatsapp_channel.inbox.messages.last
      expect(message.message_type).to eq('outgoing')
      expect(message.sender).to be_nil
      expect(message.status).to eq('delivered')
      expect(message.content_attributes['external_echo']).to be true
    end

    it 'ignores mirrored webhooks from another managed whatsapp inbox' do
      other_channel = create(:channel_whatsapp, provider: 'unoapi', sync_templates: false, validate_provider_config: false)
      mirrored_value = base_value.deep_dup
      mirrored_value[:metadata][:display_phone_number] = other_channel.phone_number.delete('+')
      mirrored_value[:metadata][:phone_number_id] = other_channel.provider_config['phone_number_id']
      mirrored_value[:contacts] = [{ profile: { name: 'Equipe Tecnica' }, wa_id: source_phone_number }]

      mirrored_params = {
        phone_number: other_channel.phone_number,
        object: 'whatsapp_business_account',
        entry: [{
          changes: [{
            value: mirrored_value
          }]
        }]
      }.with_indifferent_access

      expect do
        described_class.new(inbox: other_channel.inbox, params: mirrored_params).perform
      end.not_to change(other_channel.inbox.messages, :count)
    end
  end
end
