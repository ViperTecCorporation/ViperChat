require 'rails_helper'

RSpec.describe Whatsapp::Unoapi::OrderDocumentService do
  let(:channel) { create(:channel_whatsapp, provider: 'unoapi', sync_templates: false, validate_provider_config: false) }
  let(:signed_url) { 'https://example.com/boleto.pdf?X-Amz-Signature=test%2Fsignature&X-Amz-Expires=604800' }
  let(:pdf) { Rails.root.join('spec/assets/sample.pdf').binread }
  let(:params) do
    JSON.parse(Rails.root.join('spec/fixtures/whatsapp/unoapi/order_details_boleto.json').read).with_indifferent_access
  end
  let(:value) { params.dig(:entry, 0, :changes, 0, :value) }
  let(:payload) { value[:messages].first }
  let(:service) { Whatsapp::IncomingMessageUnoapiService.new(inbox: channel.inbox, params: params, outgoing_echo: outgoing_echo) }
  let(:outgoing_echo) { false }

  before do
    payload[:interactive][:header] = {
      type: 'document', document: { link: signed_url, filename: 'boletoTeste.pdf', mime_type: 'application/pdf' }
    }
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('example.com').and_return(['93.184.216.34'])
    stub_request(:get, signed_url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
  end

  it 'stores the PDF locally on the incoming order, preserving its identity and payment data' do
    expect(SafeFetch).to receive(:fetch).with(signed_url, anything).and_call_original
    expect { service.perform }.to change(channel.inbox.messages, :count).by(1)
    message = channel.inbox.messages.find_by!(source_id: payload[:id])
    expect(message.content).to eq('Pague o pedido')
    expect(message.content_attributes.dig('whatsapp_interactive', 'type')).to eq('order_details')
    expect(message.content_attributes.dig('whatsapp_interactive', 'order', 'payment_settings').first['type']).to eq('boleto')
    expect(message.content_attributes.to_json).not_to include('X-Amz-Signature')
    expect(message.attachments.count).to eq(1)
  end

  it 'preserves the document filename, MIME and bytes in local storage' do
    service.perform
    attachment = channel.inbox.messages.find_by!(source_id: payload[:id]).attachments.sole
    expect(attachment.file_type).to eq('file')
    expect(attachment.file.filename.to_s).to eq('boletoTeste.pdf')
    expect(attachment.file.content_type).to eq('application/pdf')
    expect(attachment.file.download).to eq(pdf)
  end

  it 'keeps PIX and buttons alongside the document and boleto' do
    payload[:interactive][:action][:parameters][:payment_settings] << {
      type: 'pix_dynamic_code', pix_dynamic_code: { merchant_name: 'Loja', key: 'pix-key', code: 'sensitive-code' }
    }
    payload[:interactive][:action][:buttons] = [{ type: 'cta_copy', copy_code: { title: 'Copiar PIX', code: 'pix-copy-code' } }]
    service.perform
    message = channel.inbox.messages.find_by!(source_id: payload[:id])
    interactive = message.content_attributes['whatsapp_interactive']
    expect(interactive.dig('order', 'payment_settings').pluck('type')).to eq(%w[boleto pix_dynamic_code])
    expect(interactive['actions']).to include('type' => 'copy', 'title' => 'Copiar PIX', 'code' => 'pix-copy-code')
    expect(message.attachments.count).to eq(1)
    expect(payload[:type]).to eq('interactive')
  end

  it 'does not duplicate the order, attachment or download on webhook replay' do
    service.perform
    service.perform
    expect(channel.inbox.messages.where(source_id: payload[:id]).count).to eq(1)
    expect(channel.inbox.messages.find_by!(source_id: payload[:id]).attachments.count).to eq(1)
    expect(a_request(:get, signed_url)).to have_been_made.once
  end

  it 'keeps the order after a failed download and can attach the PDF on replay' do
    stub_request(:get, signed_url).to_return(status: 403)
    service.perform
    message = channel.inbox.messages.find_by!(source_id: payload[:id])
    expect(message.content).to eq('Pague o pedido')
    expect(message.attachments).to be_empty
    stub_request(:get, signed_url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
    expect { service.perform }.not_to change(channel.inbox.messages, :count)
    expect(message.reload.attachments.sole.file.download).to eq(pdf)
  end

  it 'rejects private network downloads without losing the order' do
    allow(Resolv).to receive(:getaddresses).with('example.com').and_return(['127.0.0.1'])
    service.perform
    expect(channel.inbox.messages.find_by!(source_id: payload[:id]).attachments).to be_empty
    expect(a_request(:get, signed_url)).not_to have_been_made
  end

  it 'does not change other interactive message types' do
    payload[:interactive][:type] = 'button'
    service.perform
    expect(channel.inbox.messages.find_by!(source_id: payload[:id]).attachments).to be_empty
    expect(a_request(:get, signed_url)).not_to have_been_made
  end

  context 'with an outgoing echo' do
    let(:outgoing_echo) { true }

    it 'stores and deduplicates the PDF in the same outgoing order' do
      original = payload
      original[:to] = original.delete(:from)
      value[:message_echoes] = value.delete(:messages)
      service.perform
      service.perform
      message = channel.inbox.messages.find_by!(source_id: original[:id])
      expect(message).to be_outgoing
      expect(message.content_attributes.dig('whatsapp_interactive', 'type')).to eq('order_details')
      expect(message.attachments.sole.file.download).to eq(pdf)
      expect(channel.inbox.messages.count).to eq(1)
      expect(a_request(:get, signed_url)).to have_been_made.once
    end
  end
end
