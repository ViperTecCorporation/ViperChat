require 'rails_helper'

describe Integrations::Typebot::ProcessorService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:hook) do
    create(
      :integrations_hook,
      app_id: 'typebot',
      inbox: inbox,
      account: account,
      settings: { 'typebot_url' => 'https://typebot.io', 'typebot_id' => 'my-bot-123' }
    )
  end
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :pending) }
  let(:message) { create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'Hi there') }
  let(:event_name) { 'message.created' }
  let(:event_data) { { message: message } }
  let(:processor) { described_class.new(event_name: event_name, hook: hook, event_data: event_data) }

  describe '#perform' do
    context 'when starting a new chat session' do
      before do
        # Mock Start Chat Response
        start_response = double(
          success?: true,
          parsed_response: {
            'sessionId' => 'session-abc-123',
            'messages' => [
              { 'type' => 'text', 'content' => 'Hello! Welcome to Typebot.' }
            ],
            'clientSideActions' => [],
            'input' => nil
          }
        )
        allow(HTTParty).to receive(:post).with(
          'https://typebot.io/api/v1/typebots/my-bot-123/startChat',
          anything
        ).and_return(start_response)

        # Mock Continue Chat Response
        continue_response = double(
          success?: true,
          parsed_response: {
            'messages' => [
              { 'type' => 'text', 'content' => 'How can I assist you today?' }
            ],
            'clientSideActions' => [],
            'input' => nil
          }
        )
        allow(HTTParty).to receive(:post).with(
          'https://typebot.io/api/v1/sessions/session-abc-123/continueChat',
          anything
        ).and_return(continue_response)
      end

      it 'calls startChat, saves the session_id, calls continueChat, and creates outgoing messages' do
        expect(conversation.custom_attributes['typebot_session_id']).to be_nil

        expect { processor.perform }.to change { conversation.reload.messages.count }.by(2)

        expect(conversation.custom_attributes['typebot_session_id']).to eq('session-abc-123')
        messages = conversation.messages.where(message_type: :outgoing).order(:created_at)
        expect(messages.first.content).to eq('Hello! Welcome to Typebot.')
        expect(messages.last.content).to eq('How can I assist you today?')
      end
    end

    context 'when continuing an existing chat session' do
      before do
        conversation.custom_attributes['typebot_session_id'] = 'existing-session-456'
        conversation.save!

        continue_response = double(
          success?: true,
          parsed_response: {
            'messages' => [
              { 'type' => 'text', 'content' => 'Here is your order status.' }
            ],
            'clientSideActions' => [],
            'input' => nil
          }
        )
        allow(HTTParty).to receive(:post).with(
          'https://typebot.io/api/v1/sessions/existing-session-456/continueChat',
          anything
        ).and_return(continue_response)
      end

      it 'does not call startChat but calls continueChat directly' do
        expect(HTTParty).not_to receive(:post).with(
          'https://typebot.io/api/v1/typebots/my-bot-123/startChat',
          anything
        )

        expect { processor.perform }.to change { conversation.reload.messages.count }.by(1)
        expect(conversation.messages.last.content).to eq('Here is your order status.')
      end
    end

    context 'when processing choice inputs' do
      before do
        conversation.custom_attributes['typebot_session_id'] = 'existing-session-456'
        conversation.save!

        continue_response = double(
          success?: true,
          parsed_response: {
            'messages' => [
              { 'type' => 'text', 'content' => 'Pick one option:' }
            ],
            'clientSideActions' => [],
            'input' => {
              'type' => 'choice input',
              'options' => [
                { 'value' => 'Option A' },
                { 'value' => 'Option B' }
              ]
            }
          }
        )
        allow(HTTParty).to receive(:post).and_return(continue_response)
      end

      it 'creates an input_select message with options' do
        processor.perform
        last_message = conversation.reload.messages.last
        expect(last_message.content_type).to eq('input_select')
        expect(last_message.content).to eq('Select an option')
        expect(last_message.content_attributes['items']).to eq([
          { 'title' => 'Option A', 'value' => 'Option A' },
          { 'title' => 'Option B', 'value' => 'Option B' }
        ])
      end
    end

    context 'when handoff action is triggered' do
      before do
        conversation.custom_attributes['typebot_session_id'] = 'existing-session-456'
        conversation.save!

        continue_response = double(
          success?: true,
          parsed_response: {
            'messages' => [
              { 'type' => 'text', 'content' => 'Connecting you to an agent...' }
            ],
            'clientSideActions' => [
              { 'type' => 'chatwoot' }
            ],
            'input' => nil
          }
        )
        allow(HTTParty).to receive(:post).and_return(continue_response)
      end

      it 'hands off the conversation to human agents' do
        expect(conversation.status).to eq('pending')
        processor.perform
        expect(conversation.reload.status).to eq('open')
        expect(conversation.messages.last.content).to eq('Connecting you to an agent...')
      end
    end

    context 'when processing media messages' do
      before do
        conversation.custom_attributes['typebot_session_id'] = 'existing-session-456'
        conversation.save!

        continue_response = double(
          success?: true,
          parsed_response: {
            'messages' => [
              { 'type' => 'image', 'content' => { 'url' => 'https://example.com/image.png' } },
              { 'type' => 'video', 'content' => 'https://example.com/video.mp4' },
              { 'type' => 'audio', 'url' => 'https://example.com/audio.mp3' }
            ],
            'clientSideActions' => [],
            'input' => nil
          }
        )
        allow(HTTParty).to receive(:post).and_return(continue_response)
      end

      it 'creates media markdown embeds correctly' do
        processor.perform
        outgoing_messages = conversation.messages.where(message_type: :outgoing).order(:created_at).to_a
        expect(outgoing_messages.size).to eq(3)
        expect(outgoing_messages[0].content).to eq('![Image](https://example.com/image.png)')
        expect(outgoing_messages[1].content).to eq('[Video](https://example.com/video.mp4)')
        expect(outgoing_messages[2].content).to eq('[Audio](https://example.com/audio.mp3)')
      end
    end
  end
end
