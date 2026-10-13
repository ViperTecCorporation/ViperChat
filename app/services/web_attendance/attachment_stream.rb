class WebAttendance::AttachmentStream
  def initialize(blob, range)
    @blob = blob
    @range = range || (0...blob.byte_size)
  end

  def each
    return enum_for(:each) unless block_given?

    @blob.open do |file|
      file.seek(@range.first)
      remaining = @range.size
      while remaining.positive?
        chunk = file.read([remaining, 64.kilobytes].min)
        break unless chunk

        yield chunk
        remaining -= chunk.bytesize
      end
    end
  end
end
