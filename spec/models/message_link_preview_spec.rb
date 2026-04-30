require 'rails_helper'

RSpec.describe Message do
  describe 'link preview callback' do
    before do
      allow_any_instance_of(described_class).to receive(:reindex_for_search).and_return(true)
      allow(SendReplyJob).to receive(:perform_later)
    end

    it 'enqueues a link preview job for text messages with links' do
      expect(Messages::LinkPreviewJob).to receive(:perform_later).with(kind_of(Integer))

      create(:message, content: 'Veja https://example.com/post', message_type: :incoming, content_type: :text)
    end

    it 'enqueues a link preview job for text messages with bare domains' do
      expect(Messages::LinkPreviewJob).to receive(:perform_later).with(kind_of(Integer))

      create(:message, content: 'Veja vipertec.net', message_type: :incoming, content_type: :text)
    end

    it 'does not enqueue a link preview job for email addresses' do
      expect(Messages::LinkPreviewJob).not_to receive(:perform_later)

      create(:message, content: 'Fale em suporte@vipertec.net', message_type: :incoming, content_type: :text)
    end

    it 'does not enqueue a link preview job for text messages without links' do
      expect(Messages::LinkPreviewJob).not_to receive(:perform_later)

      create(:message, content: 'Mensagem sem link', message_type: :incoming, content_type: :text)
    end
  end
end
