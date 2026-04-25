require 'rails_helper'

RSpec.describe Messages::LinkPreviewJob do
  describe '#perform' do
    it 'runs the link preview service for the message' do
      message = create(:message, content: 'https://example.com/post')
      service = instance_double(Messages::LinkPreviewService)

      allow(Messages::LinkPreviewService).to receive(:new).with(message).and_return(service)
      allow(service).to receive(:perform)

      described_class.perform_now(message.id)

      expect(service).to have_received(:perform)
    end
  end
end
