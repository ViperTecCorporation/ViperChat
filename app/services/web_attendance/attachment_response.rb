class WebAttendance::AttachmentResponse
  class InvalidRange < StandardError; end

  def initialize(blob:, range_header:, download:)
    @blob = blob
    @download = download
    @range = parse_range(range_header)
  end

  def apply(response)
    response.headers.merge!(headers)
    response.status = :partial_content if @range
    WebAttendance::AttachmentStream.new(@blob, @range)
  end

  private

  def parse_range(header)
    return if header.blank?

    ranges = Rack::Utils.get_byte_ranges(header, @blob.byte_size)
    raise InvalidRange if ranges.nil? || ranges.size != 1

    ranges.first
  end

  def disposition
    return 'attachment' if @download

    @blob.content_type&.match?(%r{\A(image/(jpeg|png|gif|webp)|video/|audio/)}) ? 'inline' : 'attachment'
  end

  def headers
    result = {
      'Content-Type' => @blob.content_type,
      'Content-Disposition' => ActionDispatch::Http::ContentDisposition.format(disposition: disposition, filename: @blob.filename.to_s),
      'Accept-Ranges' => 'bytes',
      'Last-Modified' => @blob.created_at.httpdate,
      'Content-Length' => (@range ? @range.size : @blob.byte_size).to_s
    }
    result['Content-Range'] = "bytes #{@range.first}-#{@range.last}/#{@blob.byte_size}" if @range
    result
  end
end
