require 'rails_helper'

RSpec.describe Whatsapp::Unoapi::InteractiveMessageNormalizer do
  let(:fixture_path) { Rails.root.join('spec/fixtures/whatsapp/unoapi') }

  def extracted_message(name)
    payload = JSON.parse(File.read(fixture_path.join(name))).with_indifferent_access
    Whatsapp::Unoapi::WebhookPayloadExtractor.new(params: payload).perform.messages.first
  end

  it 'normalizes all documented interactive fixtures without raising' do
    fixtures = %w[
      interactive_button.json interactive_cta.json interactive_list.json interactive_button_reply.json
      interactive_list_reply.json interactive_carousel_action.json interactive_carousel_root.json
      payment_request_static_pix.json payment_request_dynamic_pix.json order_details_payment_link.json
      order_details_pix.json order_details_boleto.json order_details_card.json order_status.json
      outgoing_echo_interactive.json
    ]

    fixtures.each do |name|
      result = described_class.new(message: extracted_message(name)).perform
      expect(result).to include(:content, :content_type, :content_attributes), name
      expect(result.dig(:content_attributes, :whatsapp_interactive, :schema_version)).to eq(1), name
    end
  end

  it 'preserves button and list reply identifiers and descriptions' do
    button = described_class.new(message: extracted_message('interactive_button_reply.json')).perform
    list = described_class.new(message: extracted_message('interactive_list_reply.json')).perform

    expect(button.dig(:content_attributes, :whatsapp_interactive, :reply)).to eq(id: 'financeiro', title: 'Financeiro')
    expect(list.dig(:content_attributes, :whatsapp_interactive, :reply)).to eq(
      id: 'segunda_via', title: 'Segunda via', description: 'Emitir uma nova via do boleto'
    )
  end

  it 'accepts cards below action.carousel and interactive.carousel' do
    action_result = described_class.new(message: extracted_message('interactive_carousel_action.json')).perform
    root_result = described_class.new(message: extracted_message('interactive_carousel_root.json')).perform

    expect(action_result[:content_attributes][:items].first[:description]).to eq('Plano completo')
    expect(root_result[:content_attributes][:items].first[:title]).to eq('Plano básico')
  end

  it 'never persists credentials or a complete dynamic PIX code' do
    pix = described_class.new(message: extracted_message('order_details_pix.json')).perform.to_json
    card = described_class.new(message: extracted_message('order_details_card.json')).perform.to_json

    expect(pix).not_to include('000201SEGREDO')
    expect(pix).to include('has_dynamic_code')
    expect(card).not_to include('credential_id', 'SEGREDO_NAO_PERSISTIR')
  end

  it 'keeps an unknown type safe as an unsupported textual message' do
    result = described_class.new(message: { type: 'interactive', interactive: { type: 'future_type' } }).perform

    expect(result[:content_type]).to eq('text')
    expect(result.dig(:content_attributes, :whatsapp_interactive, :unsupported)).to be(true)
  end
end
