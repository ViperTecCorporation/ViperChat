class Voip::RecordingClient < Voip::ServiceHistoryClient
  MIME_TYPES = %w[audio/mpeg audio/mp3 audio/wav audio/wave audio/x-wav audio/gsm audio/x-gsm audio/ogg].freeze
  MAX_RECORDING_BYTES = 50.megabytes

  def fetch(recording)
    file = Tempfile.new(['voip-recording', '.audio'], binmode: true)
    digest = Digest::SHA256.new
    mime = read_recording(recording, file, digest)
    validate_recording!(recording, file, digest)
    file.rewind
    { file: file, mime: mime, digest: digest.hexdigest }
  rescue StandardError
    file&.close!
    raise ResponseError, 'Recording fetch failed', cause: nil
  end

  private

  def recording_options(recording)
    uri = configured_uri!
    uri.path = "#{uri.path.delete_suffix('/')}/v1/console/history-records/#{ERB::Util.url_encode(recording.fetch('record_id'))}/recording"
    SafeFetch::RequestOptions.new(url: uri.to_s, open_timeout: 3, read_timeout: 15,
                                  headers: { 'Authorization' => "Bearer #{credentials['history_api_token']}" })
  end

  def read_recording(recording, file, digest)
    mime = nil
    perform_request(recording_options(recording)) do |response|
      mime = response['content-type'].to_s.split(';').first.to_s.downcase
      raise ResponseError, 'Invalid recording response' unless response.code.to_i == 200 && MIME_TYPES.include?(mime)
      raise ResponseError, 'Recording exceeds limit' if response['content-length'].to_i > MAX_RECORDING_BYTES

      response.read_body do |chunk|
        raise ResponseError, 'Recording exceeds limit' if file.size + chunk.bytesize > MAX_RECORDING_BYTES

        file.write(chunk)
        digest.update(chunk)
      end
    end
    mime
  end

  def validate_recording!(recording, file, digest)
    bytes = file.size
    raise ResponseError, 'Empty recording' if bytes.zero?
    raise ResponseError, 'Recording size mismatch' if recording['size_bytes'] && recording['size_bytes'] != file.size
    raise ResponseError, 'Recording hash mismatch' if recording['sha256'] && recording['sha256'] != digest.hexdigest
  end
end
