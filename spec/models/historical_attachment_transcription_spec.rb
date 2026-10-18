require 'rails_helper'

RSpec.describe Enterprise::Concerns::Attachment do
  let(:message) { build(:message, content_attributes: { 'whatsapp_history_import' => true }) }
  let(:attachment) { Attachment.new(message: message, file_type: :audio) }

  it 'does not automatically transcribe an imported historical audio' do
    expect(Messages::AudioTranscriptionJob).not_to receive(:perform_later)
    attachment.send(:enqueue_audio_transcription)
  end

  it 'keeps automatic transcription for an eligible live audio' do
    message.content_attributes = {}
    allow(attachment).to receive(:eligible_for_audio_transcription?).and_return(true)
    expect(Messages::AudioTranscriptionJob).to receive(:perform_later).with(nil)
    attachment.send(:enqueue_audio_transcription)
  end
end
