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
end
