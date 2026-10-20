require 'rails_helper'

RSpec.describe Whatsapp::TemplateDefinition do
  let(:attributes) { { name: 'order_update', language: 'pt_BR', category: 'UTILITY', body: 'Pedido recebido.' } }

  %w[MARKETING UTILITY].each do |category|
    it "builds a text-only #{category} definition without requiring variables" do
      payload = described_class.new(attributes.merge(category: category)).payload

      expect(payload).to eq('name' => 'order_update', 'language' => 'pt_BR', 'category' => category,
                            'parameter_format' => 'POSITIONAL', 'components' => [{ 'type' => 'BODY', 'text' => 'Pedido recebido.' }])
    end
  end

  it 'builds text header, body, footer and static URL buttons, ignoring arbitrary Graph fields' do
    definition = described_class.new(attributes.merge(header: 'Seu pedido', footer: 'Obrigado!',
                                                      buttons: [{ type: 'URL', text: 'Ver', url: 'https://example.com/order', secret: 'discard' }],
                                                      access_token: 'discard', components: [{ type: 'IMAGE' }]))

    expect(definition.payload['components']).to eq([
                                                     { 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Seu pedido' },
                                                     { 'type' => 'BODY', 'text' => 'Pedido recebido.' },
                                                     { 'type' => 'FOOTER', 'text' => 'Obrigado!' },
                                                     { 'type' => 'BUTTONS', 'buttons' => [
                                                       { 'type' => 'URL', 'text' => 'Ver', 'url' => 'https://example.com/order' }
                                                     ] }
                                                   ])
    expect(definition.payload.to_json).not_to include('discard', 'IMAGE', 'access_token')
  end

  it 'uses one example per sequential position even when a variable is repeated' do
    payload = described_class.new(attributes.merge(body: 'Olá {{1}}, pedido {{2}}. Obrigado {{1}}!', examples: %w[Ana 123])).payload

    expect(payload['components']).to eq([{ 'type' => 'BODY', 'text' => 'Olá {{1}}, pedido {{2}}. Obrigado {{1}}!',
                                           'example' => { 'body_text' => [%w[Ana 123]] } }])
  end

  ['{{2}}', '{{1}} {{3}}', '{{2}} {{1}}', '{{0}}', '{{01}}', '{{name}}', '{{1}', '{1}', '{{ 1 }}'].each do |body|
    it "rejects invalid or nonsequential placeholders #{body.inspect}" do
      definition = described_class.new(attributes.merge(body: body, examples: ['Ana']))

      expect(definition).not_to be_valid
      expect(definition.errors.where(:body)).to be_present
    end
  end

  [nil, 'Ana', [], [''], [' '], [1], ['Ana', 'extra'], ['x' * 1025]].each do |examples|
    it "rejects missing, blank, incorrectly typed or excess examples #{examples.inspect[0, 50]}" do
      definition = described_class.new(attributes.merge(body: 'Olá {{1}}', examples: examples))

      expect(definition).not_to be_valid
      expect(definition.errors.where(:examples)).to be_present
    end
  end

  it 'rejects examples on a body with no variables' do
    expect(described_class.new(attributes.merge(examples: ['unused']))).not_to be_valid
  end

  { name: 512, body: 1024, header: 60, footer: 60 }.each do |field, limit|
    it "accepts #{field} at #{limit} characters and rejects one character more" do
      expect(described_class.new(attributes.merge(field => 'a' * limit))).to be_valid
      definition = described_class.new(attributes.merge(field => 'a' * (limit + 1)))

      expect(definition).not_to be_valid
      expect(definition.errors.where(field)).to be_present
    end
  end

  [[:name, 'Invalid Name'], [:name, ''], [:language, 'pt-br'], [:language, nil], [:category, 'AUTHENTICATION'],
   [:body, ' '], [:body, nil], [:body, 123], [:header, '{{1}}'], [:footer, '{{name}}']].each do |field, value|
    it "rejects unsupported #{field} #{value.inspect}" do
      definition = described_class.new(attributes.merge(field => value))
      expect(definition).not_to be_valid
      expect(definition.errors.where(field)).to be_present
    end
  end

  it 'accepts three quick replies, two URL buttons and a 25-character button label' do
    replies = Array.new(3) { { type: 'QUICK_REPLY', text: 'a' * 25 } }
    urls = Array.new(2) { { type: 'URL', text: 'Abrir', url: 'https://example.com' } }

    expect(described_class.new(attributes.merge(buttons: replies))).to be_valid
    expect(described_class.new(attributes.merge(buttons: urls))).to be_valid
  end

  [nil, {}, ['not-a-button'], [{ type: 'PHONE_NUMBER', text: 'Ligar' }],
   [{ type: 'QUICK_REPLY', text: '' }], [{ type: 'QUICK_REPLY', text: 'x' * 26 }],
   [{ type: 'QUICK_REPLY', text: '{{1}}' }], Array.new(4) { { type: 'QUICK_REPLY', text: 'OK' } },
   Array.new(3) { { type: 'URL', text: 'Abrir', url: 'https://example.com' } },
   [{ type: 'QUICK_REPLY', text: 'OK' }, { type: 'URL', text: 'Abrir', url: 'https://example.com' }]].each_with_index do |buttons, index|
    it "rejects invalid button type, label, count or mixtures (#{index})" do
      definition = described_class.new(attributes.merge(buttons: buttons))
      expect(definition).not_to be_valid
      expect(definition.errors.where(:buttons)).to be_present
    end
  end

  [nil, 'http://example.com', 'javascript:alert(1)', '/relative', 'https://', 'https://user:password@example.com',
   'https://example.com/{{1}}', 'https://example.com/a b', "https://example.com/#{'a' * 2000}"].each do |url|
    it "rejects unsafe or unsupported button URL #{url.inspect[0, 65]}" do
      definition = described_class.new(attributes.merge(buttons: [{ type: 'URL', text: 'Abrir', url: url }]))

      expect(definition).not_to be_valid
      expect(definition.errors.where(:buttons)).to be_present
    end
  end

  it 'does not permit payload generation for an invalid definition' do
    expect { described_class.new(attributes.merge(body: '')).payload }.to raise_error do |error|
      expect(error.class.name).to eq('ActiveModel::ValidationError')
    end
  end
end
