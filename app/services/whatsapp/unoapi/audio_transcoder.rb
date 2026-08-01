require 'open3'
require 'tempfile'

class Whatsapp::Unoapi::AudioTranscoder
  OGG_CONTENT_TYPES = %w[audio/ogg audio/opus].freeze
  OGG_EXTENSIONS = %w[.oga .ogg .opus].freeze
  MP3_OUTPUT_OPTIONS = %w[
    -vn
    -ar 48000
    -ac 1
    -c:a libmp3lame
    -b:a 64k
    -map_metadata -1
    -f mp3
  ].freeze

  class Error < StandardError; end

  def initialize(file)
    @file = file
  end

  def perform
    return file unless ogg_audio?

    output = Tempfile.new(['unoapi-audio-', '.mp3'])
    output.binmode
    output.close

    transcode(output.path)
    output.open
    output.binmode
    output.rewind
    add_file_metadata(output)
    close_input
    output
  rescue StandardError
    output&.close!
    close_input
    raise
  end

  private

  attr_reader :file

  def ogg_audio?
    content_type = file.content_type.to_s.downcase.split(';').first
    extension = File.extname(file.original_filename.to_s).downcase
    OGG_CONTENT_TYPES.include?(content_type) || OGG_EXTENSIONS.include?(extension)
  end

  def transcode(output_path)
    _, stderr, status = Open3.capture3(
      'ffmpeg',
      '-hide_banner',
      '-loglevel',
      'error',
      '-y',
      '-i',
      file.path,
      *MP3_OUTPUT_OPTIONS,
      output_path
    )
    return if status.success?

    raise Error, "UnoAPI audio conversion failed: #{stderr.to_s.strip.first(500)}"
  rescue Errno::ENOENT
    raise Error, 'UnoAPI audio conversion failed: ffmpeg is not installed'
  end

  def add_file_metadata(output)
    filename = mp3_filename
    output.define_singleton_method(:original_filename) { filename }
    output.define_singleton_method(:content_type) { 'audio/mpeg' }
  end

  def mp3_filename
    basename = File.basename(file.original_filename.to_s, '.*')
    basename = 'audio' if basename.empty?
    "#{basename}.mp3"
  end

  def close_input
    file.close! if file.respond_to?(:close!)
  end
end
