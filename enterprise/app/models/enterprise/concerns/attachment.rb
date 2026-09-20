module Enterprise::Concerns::Attachment
  extend ActiveSupport::Concern

  included do
    after_create_commit :enqueue_audio_transcription
  end

  def eligible_for_audio_transcription?
    audio? && message.incoming? && !message.private?
  end

  private

  def enqueue_audio_transcription
    return unless eligible_for_audio_transcription?

    Messages::AudioTranscriptionJob.perform_later(id)
  end
end
