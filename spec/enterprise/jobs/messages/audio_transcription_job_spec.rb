require 'rails_helper'

RSpec.describe Messages::AudioTranscriptionJob do
  subject(:job) { described_class.perform_later(attachment_id) }

  let(:message) { create(:message, message_type: message_type, private: private_message) }
  let(:message_type) { :incoming }
  let(:private_message) { false }
  let(:attachment) do
    message.attachments.create!(
      account_id: message.account_id,
      file_type: :audio,
      file: fixture_file_upload('public/audio/widget/ding.mp3')
    )
  end
  let(:attachment_id) { attachment.id }
  let(:conversation) { message.conversation }
  let(:transcription_service) { instance_double(Messages::AudioTranscriptionService) }

  it 'enqueues the job' do
    expect { job }.to have_enqueued_job(described_class)
      .with(attachment_id)
      .on_queue('low')
  end

  context 'when performing the job' do
    before do
      allow(Messages::AudioTranscriptionService).to receive(:new).with(attachment).and_return(transcription_service)
      allow(transcription_service).to receive(:perform)
    end

    it 'calls AudioTranscriptionService with the attachment' do
      expect(Messages::AudioTranscriptionService).to receive(:new).with(attachment)
      expect(transcription_service).to receive(:perform)
      described_class.perform_now(attachment_id)
    end

    it 'does nothing when attachment is not found' do
      expect(Messages::AudioTranscriptionService).not_to receive(:new)
      described_class.perform_now(999_999)
    end
  end

  describe 'automatic transcription eligibility' do
    it 'enqueues transcription for customer audio' do
      expect { attachment }.to have_enqueued_job(described_class)
    end

    context 'with outgoing agent audio' do
      let(:message_type) { :outgoing }

      it 'does not enqueue transcription' do
        expect { attachment }.not_to have_enqueued_job(described_class)
      end

      it 'ignores an already queued job' do
        expect(Messages::AudioTranscriptionService).not_to receive(:new)
        described_class.perform_now(attachment_id)
      end
    end

    context 'with a private note' do
      let(:private_message) { true }

      it 'does not enqueue transcription even when marked incoming' do
        expect { attachment }.not_to have_enqueued_job(described_class)
      end

      it 'ignores an already queued job' do
        expect(Messages::AudioTranscriptionService).not_to receive(:new)
        described_class.perform_now(attachment_id)
      end
    end
  end
end
