require 'rails_helper'

describe MessageTemplates::Template::OutOfOffice do
  context 'when this hook is called' do
    let(:conversation) { create(:conversation) }

    it 'creates the out of office messages' do
      described_class.new(conversation: conversation).perform
      expect(conversation.messages.template.count).to eq(1)
      expect(conversation.messages.template.first.content).to eq(conversation.inbox.out_of_office_message)
    end

    it 'creates the out of office messages with template variable' do
      conversation.inbox.update!(out_of_office_message: 'Hey, {{contact.name}} we are unavailable at the moment.')
      described_class.new(conversation: conversation).perform
      expect(conversation.messages.count).to eq(1)
      expect(conversation.messages.last.content).to eq("Hey, #{conversation.contact.name} we are unavailable at the moment.")
    end

    it 'creates the out of office messages with more than one variable strings' do
      conversation.inbox.update!(out_of_office_message:
        'Hey, {{contact.name}} we are unavailable at the moment. - from {{account.name}}')
      described_class.new(conversation: conversation).perform
      expect(conversation.messages.count).to eq(1)
      expect(conversation.messages.last.content).to eq(
        "Hey, #{conversation.contact.name} we are unavailable at the moment. - from #{conversation.account.name}"
      )
    end

    it 'does not create the out of office message for group conversations by default' do
      conversation.update!(group: true)

      described_class.new(conversation: conversation).perform

      expect(conversation.messages.template.count).to eq(0)
    end

    it 'creates the out of office message for group conversations when enabled on inbox' do
      conversation.update!(group: true)
      conversation.inbox.update!(out_of_office_send_to_groups: true)

      described_class.new(conversation: conversation).perform

      expect(conversation.messages.template.count).to eq(1)
    end
  end
end
