require 'rails_helper'

RSpec.describe Messages::LinkPreviewService do
  let(:url) { 'https://example.com/post' }
  let(:message) { create(:message, content: "Confira (#{url}).", message_type: :incoming, content_type: :text) }

  before do
    allow(Messages::LinkPreviewJob).to receive(:perform_later)
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('example.com').and_return(['93.184.216.34'])
  end

  describe '#perform' do
    it 'stores the first link preview in content attributes' do
      stub_request(:get, url).to_return(
        status: 200,
        body: <<~HTML,
          <html>
            <head>
              <meta property="og:title" content="Example title">
              <meta name="description" content="Example description">
              <meta property="og:image" content="/preview.png">
              <meta property="og:site_name" content="Example Site">
              <link rel="icon" href="/favicon.ico">
            </head>
          </html>
        HTML
        headers: { 'Content-Type' => 'text/html; charset=utf-8' }
      )

      described_class.new(message).perform

      expect(message.reload.link_preview).to include(
        'url' => url,
        'title' => 'Example title',
        'description' => 'Example description',
        'image_url' => 'https://example.com/preview.png',
        'site_name' => 'Example Site',
        'favicon_url' => 'https://example.com/favicon.ico'
      )
    end

    it 'does not store a preview when the page has no metadata' do
      stub_request(:get, url).to_return(
        status: 200,
        body: '<html><head></head><body></body></html>',
        headers: { 'Content-Type' => 'text/html' }
      )

      described_class.new(message).perform

      expect(message.reload.link_preview).to be_nil
    end

    it 'skips preview failures without raising' do
      allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::UnsafeUrlError, 'blocked')

      expect { described_class.new(message).perform }.not_to raise_error
      expect(message.reload.link_preview).to be_nil
    end
  end
end
