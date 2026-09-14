require 'rails_helper'

RSpec.describe Whatsapp::Unoapi::StickerTranscoder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  it 'converts a large JPEG to a metadata-free WebP within WhatsApp sticker limits' do
    source = Tempfile.new(['large-sticker-', '.jpeg'])
    source.close
    Vips::Image.gaussnoise(1400, 900, sigma: 60).cast(:uchar).write_to_file(source.path, Q: 95)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: File.open(source.path, 'rb'), filename: 'FazOPix.jpeg', content_type: 'image/jpeg'
    )
    sticker = WhatsappSticker.create!(account: account, inbox: inbox, blob: blob)

    result = described_class.new(sticker).perform
    dimensions = result.blob.open { |file| Vips::Image.new_from_file(file.path).then { |image| [image.width, image.height] } }

    expect(blob.byte_size).to be > 100_000
    expect(result.blob).to have_attributes(content_type: 'image/webp')
    expect(result.blob.filename.to_s).to eq('FazOPix.webp')
    expect(result.blob.byte_size).to be <= 100_000
    expect(dimensions).to eq([512, 329])
    expect(sticker.reload.blob).to eq(result.blob)
  ensure
    source&.close!
  end

  it 'keeps an already valid WebP without creating another blob' do
    source = Tempfile.new(['valid-sticker-', '.webp'])
    source.close
    Vips::Image.black(256, 128).write_to_file(source.path, Q: 80, strip: true)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: File.open(source.path, 'rb'), filename: 'valid.webp', content_type: 'image/webp'
    )
    sticker = WhatsappSticker.create!(account: account, inbox: inbox, blob: blob)

    expect(described_class.new(sticker).perform).to eq(sticker)
    expect(sticker.reload.blob).to eq(blob)
  ensure
    source&.close!
  end

  it 'raises a specific error when image conversion fails' do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new('not-an-image'), filename: 'broken.jpeg', content_type: 'image/jpeg'
    )
    sticker = WhatsappSticker.create!(account: account, inbox: inbox, blob: blob)

    expect { described_class.new(sticker).perform }
      .to raise_error(described_class::Error, /UnoAPI sticker conversion failed/)
  end
end
