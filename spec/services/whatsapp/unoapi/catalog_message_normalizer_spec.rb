require 'rails_helper'

RSpec.describe Whatsapp::Unoapi::CatalogMessageNormalizer do
  let(:fixture_path) { Rails.root.join('spec/fixtures/whatsapp/unoapi') }

  def extracted_message(name)
    payload = JSON.parse(File.read(fixture_path.join(name))).with_indifferent_access
    Whatsapp::Unoapi::WebhookPayloadExtractor.new(params: payload).perform.messages.first
  end

  it 'normalizes product and every documented order resolution without losing the textual fallback' do
    fixtures = %w[catalog_product.json catalog_order_resolved.json catalog_order_summary.json catalog_order_failed.json]

    fixtures.each do |name|
      result = described_class.new(message: extracted_message(name)).perform
      expect(result[:content]).to be_present, name
      expect(result[:content_attributes]['unoapi_message_type']).to be_in(%w[product order]), name
    end
  end

  it 'preserves amount_1000 values without applying an offset conversion' do
    result = described_class.new(message: extracted_message('catalog_product.json')).perform
    catalog = result[:content_attributes]['unoapi_catalog']

    expect(catalog['price_amount_1000']).to eq(129_900)
    expect(catalog['sale_price_amount_1000']).to eq(119_900)
  end

  it 'removes credentials and internal transport secrets recursively' do
    message = extracted_message('catalog_product.json')
    message[:product][:credential_id] = 'secret'
    message[:product][:metadata] = { direct_path: 'secret-path', token: 'secret-token' }

    result = described_class.new(message: message).perform.to_json

    expect(result).not_to include('credential_id', 'secret-path', 'secret-token')
  end
end
