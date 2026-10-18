require 'rails_helper'

RSpec.describe Whatsapp::IncomingMessageWhatsappCloudService do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:value) do
    { metadata: { display_phone_number: channel.phone_number.delete('+') },
      contacts: [{ wa_id: '5566996269251', profile: { name: 'Participante' } }],
      messages: [{ id: 'group-public-id', from: '5566996269251', group_id: '120363040468224',
                   timestamp: Time.current.to_i.to_s, type: 'text', text: { body: 'Grupo' } }] }.with_indifferent_access
  end
  let(:params) { { entry: [{ changes: [{ field: 'messages', value: value }] }] }.with_indifferent_access }

  it 'persists the exact Meta group separately from the real sender and deduplicates a replay before any media download' do # rubocop:disable RSpec/MultipleExpectations
    described_class.new(inbox: channel.inbox, params: params).perform
    conversation = channel.inbox.conversations.find_by!(group_source_id: '120363040468224')
    message = conversation.messages.incoming.sole
    expect(conversation).to be_group
    expect(message.sender).not_to eq(conversation.contact)
    expect(message.sender.name).to eq('Participante')
    expect(conversation.group_contacts.sole.contact).to eq(message.sender)
    expect(Whatsapp::Unoapi::GroupParticipantsSyncJob).not_to have_been_enqueued
    replay = params.deep_dup
    replay[:entry][0][:changes][0][:value][:messages][0].merge!(type: 'image', image: { id: 'should-not-download' })
    expect(Down).not_to receive(:download)
    expect { described_class.new(inbox: channel.inbox, params: replay).perform }.not_to change(Message, :count)
    expect(message.reload.source_id).to eq('group-public-id')
  end

  it 'records an outgoing echo as a group message, without making the group ID a phone' do
    value[:message_echoes] = value.delete(:messages)
    value[:message_echoes][0].merge!(from: channel.phone_number.delete('+'), to: '120363040468224')
    described_class.new(inbox: channel.inbox, params: params, outgoing_echo: true).perform
    conversation = channel.inbox.conversations.find_by!(group_source_id: '120363040468224')
    message = conversation.messages.outgoing.sole
    expect(message.sender).to be_nil
    expect(message.content_attributes['external_echo']).to be(true)
    expect(conversation.contact.phone_number).to be_blank
  end

  it 'updates group status and ignores it when the administrator enables the filter' do
    described_class.new(inbox: channel.inbox, params: params).perform
    message = channel.inbox.messages.incoming.sole
    value.delete(:messages)
    value.delete(:contacts)
    value[:statuses] = [{ id: message.source_id, recipient_id: '120363040468224', recipient_type: 'group', status: 'delivered' }]
    described_class.new(inbox: channel.inbox, params: params).perform
    expect(message.reload.status).to eq('delivered')
    channel.update_columns(provider_config: channel.provider_config.merge('ignore_group_messages' => true)) # rubocop:disable Rails/SkipsModelValidations
    value[:statuses][0][:status] = 'read'
    described_class.new(inbox: channel.inbox, params: params).perform
    expect(message.reload.status).to eq('delivered')
  end

  %i[unoapi whatsapp_cloud].each do |principal|
    it "retains live Uno group ingestion when #{principal} is primary, even if Meta ignores groups" do
      uno = create(:channel_whatsapp, account: channel.account, provider: 'unoapi', phone_number: '+5565998765432',
                                      provider_config: { 'use_group_conversation_schema' => true },
                                      sync_templates: false, validate_provider_config: false)
      channel.update_columns(phone_number: '+556598765432', # rubocop:disable Rails/SkipsModelValidations
                             provider_config: channel.provider_config.merge('ignore_group_messages' => true))
      pair = [uno.inbox, channel.inbox]
      pair.reverse! if principal == :whatsapp_cloud
      WhatsappInboxLink.create!(account: channel.account, primary_inbox: pair.first, secondary_inbox: pair.last,
                                default_provider: principal.to_s, enabled: true)
      group_value = params[:entry][0][:changes][0][:value]
      group_value[:messages][0][:group_id] = '120363040468224@g.us'
      group_value[:contacts][0][:group_id] = '120363040468224@g.us'
      group_value[:metadata][:display_phone_number] = uno.phone_number.delete('+')
      Whatsapp::IncomingMessageUnoapiService.new(inbox: uno.inbox, params: params).perform
      message = uno.inbox.messages.incoming.sole
      expect(message).to be_persisted
      expect(message.inbox_id).to eq(uno.inbox.id)
      expect(message.conversation.group_source_id).to eq('120363040468224@g.us')
      expect(WhatsappUnifiedEvent.count).to eq(0)
    end
  end
end
