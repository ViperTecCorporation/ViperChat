require 'rails_helper'

RSpec.describe Whatsapp::IncomingMessageUnoapiService do
  let(:channel) do
    create(
      :channel_whatsapp,
      provider: 'unoapi',
      sync_templates: false,
      validate_provider_config: false
    )
  end
  let(:conversation) { create(:conversation, account: channel.account, inbox: channel.inbox) }
  let!(:message) do
    create(
      :message,
      account: channel.account,
      inbox: channel.inbox,
      conversation: conversation,
      message_type: :outgoing,
      status: :progress,
      source_id: '2bf828c0-pix-message',
      content: 'Pix - Cnpj : 1450742000190',
      content_attributes: { whatsapp_interactive: { type: 'payment_request' } }
    )
  end

  it 'updates the synthetic PIX message through sent, received, and read statuses without duplicating it' do
    expect do
      %w[sent received read].each do |status|
        described_class.new(
          inbox: channel.inbox,
          params: {
            statuses: [{
              id: '2bf828c0-pix-message',
              status: status
            }]
          }.with_indifferent_access
        ).perform
      end
    end.not_to change(channel.inbox.messages, :count)

    expect(message.reload).to have_attributes(
      status: 'read',
      content: 'Pix - Cnpj : 1450742000190',
      source_id: '2bf828c0-pix-message'
    )
  end

  context 'when UnoAPI sends catalog messages' do
    let(:source_id) { 'uno-order-example-001' }
    let(:debug_logs) { [] }
    let(:order_payload) do
      {
        order_id: 'order-example-001',
        status: 'inquiry',
        resolution_status: 'failed',
        item_count: 1,
        items: [],
        title: 'Loja de exemplo',
        catalog_type: 'NATIVE',
        token: 'must-not-be-stored',
        image: {
          url: 'https://storage.example.test/catalog/order-example-001.jpg',
          mediaKey: 'must-not-be-stored'
        },
        metadata: {
          directPath: 'must-not-be-stored',
          order_token: 'must-not-be-stored',
          sensitive_string_value: 'must-not-be-stored'
        }
      }
    end
    let(:catalog_params) do
      {
        entry: [{
          changes: [{
            value: {
              metadata: {
                phone_number_id: channel.provider_config['phone_number_id'],
                display_phone_number: channel.phone_number.delete('+')
              },
              messages: [{
                from: '',
                from_user_id: '123456789012345@lid',
                id: source_id,
                timestamp: '1785421664',
                type: 'order',
                order: order_payload,
                fallback_text: "*Pedido recebido*\nLoja de exemplo\nItens: 1"
              }]
            }
          }]
        }]
      }.with_indifferent_access
    end

    before do
      allow(Rails.logger).to receive(:debug) do |message = nil, &block|
        debug_logs << (message || block&.call)
      end
    end

    it 'persists a failed order as one searchable text message and logs every boundary', :aggregate_failures do
      expect do
        perform_enqueued_jobs(only: ActionCableBroadcastJob) do
          described_class.new(inbox: channel.inbox, params: catalog_params).perform
        end
      end.to change { channel.inbox.messages.where(source_id: source_id).count }.from(0).to(1)

      catalog_message = channel.inbox.messages.find_by!(source_id: source_id)
      expect(catalog_message).to have_attributes(
        content: "*Pedido recebido*\nLoja de exemplo\nItens: 1",
        content_type: 'text',
        status: 'sent'
      )
      expect(catalog_message.attachments).to be_empty
      expect(catalog_message.content_attributes['unoapi_message_type']).to eq('order')
      expect(catalog_message.content_attributes['unoapi_order']).to include(
        'order_id' => 'order-example-001',
        'resolution_status' => 'failed',
        'item_count' => 1,
        'items' => []
      )
      expect(catalog_message.content_attributes.to_json).not_to match(/must-not-be-stored|mediaKey|directPath|order_token|sensitive_string_value/)
      expect(debug_logs).to include(a_string_starting_with('event=unoapi_catalog_received'))
      expect(debug_logs).to include(a_string_starting_with('event=unoapi_catalog_normalized'))
      expect(debug_logs).to include(a_string_starting_with('event=unoapi_catalog_persisted'))
      expect(debug_logs).to include(a_string_starting_with('event=unoapi_catalog_broadcast'))
    end

    it 'updates the same message on redelivery without regressing its status' do
      described_class.new(inbox: channel.inbox, params: catalog_params).perform
      catalog_message = channel.inbox.messages.find_by!(source_id: source_id)
      catalog_message.update!(status: :read)

      resolved_params = catalog_params.deep_dup
      resolved_order = resolved_params.dig(:entry, 0, :changes, 0, :value, :messages, 0, :order)
      resolved_order[:resolution_status] = 'resolved'
      resolved_order[:items] = [{ name: 'Óculos de grau', quantity: 1 }]
      resolved_params.dig(:entry, 0, :changes, 0, :value, :messages, 0)[:fallback_text] = "*Pedido recebido*\nÓculos de grau"

      expect do
        described_class.new(inbox: channel.inbox, params: resolved_params).perform
      end.not_to(change { channel.inbox.messages.where(source_id: source_id).count })

      catalog_message.reload
      expect(catalog_message.id).to eq(channel.inbox.messages.find_by!(source_id: source_id).id)
      expect(catalog_message.status).to eq('read')
      expect(catalog_message.content).to eq("*Pedido recebido*\nÓculos de grau")
      expect(catalog_message.content_attributes.dig('unoapi_order', 'resolution_status')).to eq('resolved')
      expect(catalog_message.content_attributes.dig('unoapi_order', 'items')).to eq([{ 'name' => 'Óculos de grau', 'quantity' => 1 }])
    end

    it 'creates a textual fallback when fallback_text is absent' do
      params_without_fallback = catalog_params.deep_dup
      params_without_fallback.dig(:entry, 0, :changes, 0, :value, :messages, 0).delete(:fallback_text)

      described_class.new(inbox: channel.inbox, params: params_without_fallback).perform

      expect(channel.inbox.messages.find_by!(source_id: source_id).content).to eq(
        "*Pedido recebido*\nLoja de exemplo\nItens: 1"
      )
    end

    it 'persists product data without treating its image as a separate attachment' do
      product_params = catalog_params.deep_dup
      product_message = product_params.dig(:entry, 0, :changes, 0, :value, :messages, 0)
      product_message[:id] = 'uno-product-example-001'
      product_message[:type] = 'product'
      product_message.delete(:order)
      product_message[:product] = {
        title: 'Óculos solar',
        retailer_id: 'OC-001',
        image: { url: 'https://storage.example.test/catalog/product-001.jpg' }
      }
      product_message[:fallback_text] = "*Produto compartilhado*\nÓculos solar"

      described_class.new(inbox: channel.inbox, params: product_params).perform

      catalog_message = channel.inbox.messages.find_by!(source_id: 'uno-product-example-001')
      expect(catalog_message.content).to eq("*Produto compartilhado*\nÓculos solar")
      expect(catalog_message.content_attributes['unoapi_message_type']).to eq('product')
      expect(catalog_message.content_attributes['unoapi_catalog']).to include(
        'title' => 'Óculos solar',
        'retailer_id' => 'OC-001'
      )
      expect(catalog_message.attachments).to be_empty
    end
  end
end
