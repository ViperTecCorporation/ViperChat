require 'image_processing/vips'
require 'tempfile'

class Whatsapp::Unoapi::StickerTranscoder
  MAX_BYTES = 100_000
  MAX_DIMENSION = 512
  WEBP_QUALITIES = [80, 70, 60, 50, 40, 30, 20, 10].freeze

  class Error < StandardError; end

  def initialize(sticker)
    @sticker = sticker
  end

  def perform
    sticker.with_lock do
      next sticker if valid_webp?(sticker.blob)

      convert(sticker.blob)
      sticker
    end
  rescue Error
    raise
  rescue StandardError => e
    raise Error, "UnoAPI sticker conversion failed: #{e.message}"
  end

  private

  attr_reader :sticker

  def valid_webp?(blob)
    return false unless blob.content_type == 'image/webp' && blob.byte_size <= MAX_BYTES

    dimensions = image_dimensions(blob)
    dimensions.all? { |dimension| dimension <= MAX_DIMENSION }
  rescue Vips::Error
    false
  end

  def image_dimensions(blob)
    blob.open do |file|
      image = Vips::Image.new_from_file(file.path, access: :sequential)
      return [image.width, image.height]
    end
  end

  def convert(blob)
    converted_blob = nil
    blob.open do |source|
      WEBP_QUALITIES.each do |quality|
        output = process(source, quality)
        next output.close! unless output.size <= MAX_BYTES

        converted_blob = persist(output, blob.filename.base)
        break
      end
    end
    return converted_blob if converted_blob

    raise Error, 'UnoAPI sticker conversion failed: WebP could not be compressed below 100 KB'
  end

  def process(source, quality)
    output = Tempfile.new(['unoapi-sticker-', '.webp'])
    output.binmode
    output.close
    ImageProcessing::Vips
      .source(source.path)
      .resize_to_limit(MAX_DIMENSION, MAX_DIMENSION)
      .convert('webp')
      .saver(quality: quality, strip: true)
      .call(destination: output.path)
    output.open
    output.binmode
    output
  rescue StandardError
    output&.close!
    raise
  end

  def persist(output, basename)
    output.rewind
    dimensions = Vips::Image.new_from_file(output.path, access: :sequential).then { |image| [image.width, image.height] }
    converted_blob = ActiveStorage::Blob.create_and_upload!(
      io: output,
      filename: "#{basename}.webp",
      content_type: 'image/webp',
      metadata: { width: dimensions.first, height: dimensions.last },
      identify: false
    )
    sticker.update!(blob: converted_blob)
    converted_blob
  ensure
    output.close!
  end
end
