require 'active_storage/service/s3_service'

# Pending blobs use a separate signing purpose: they cannot be attached until S3
# confirms completion. Session ownership survives multiple web/worker processes.
class Uploads::MultipartService
  PART_SIZE = 16.megabytes
  LIFETIME = 24.hours
  PURPOSE = :multipart_upload
  class InvalidUpload < StandardError; end

  attr_reader :blob

  def self.supported?
    ActiveStorage::Blob.service.is_a?(ActiveStorage::Service::S3Service)
  end

  def self.start!(attributes, owner)
    raise InvalidUpload, 'Multipart requires S3 storage' unless supported?

    validate_attributes!(attributes)
    blob = ActiveStorage::Blob.create_before_direct_upload!(**attributes)
    service = new(blob)
    blob.update!(metadata: { 'multipart' => owner.merge('expires_at' => LIFETIME.from_now.iso8601, 'state' => 'pending') })
    Uploads::CleanupMultipartJob.set(wait: LIFETIME).perform_later(blob.id)
    service.initiate!
    service
  end

  def self.validate_attributes!(attributes)
    size = Integer(attributes.fetch(:byte_size))
    limit = GlobalConfigService.load('MAXIMUM_FILE_UPLOAD_SIZE', '150').to_i.megabytes
    raise InvalidUpload, 'Invalid upload size' unless size.positive? && size <= limit && size <= PART_SIZE * 1000
    raise InvalidUpload, 'Invalid checksum' unless Base64.strict_decode64(attributes.fetch(:checksum)).bytesize == 16

    attributes[:byte_size] = size
  rescue ArgumentError, KeyError
    raise InvalidUpload, 'Invalid upload attributes'
  end

  def initialize(blob)
    @blob = blob
  end

  def session
    blob.metadata.fetch('multipart')
  end

  def initiate!
    response = client.create_multipart_upload(**blob.service.upload_options, **object_params, content_type: blob.content_type,
                                                                                              metadata: { 'chatwoot-blob-id' => blob.id.to_s })
    blob.update!(metadata: blob.metadata.deep_merge('multipart' => { 'upload_id' => response.upload_id }))
  end

  def client
    blob.service.client.client
  end

  def object_params
    { bucket: blob.service.bucket.name, key: blob.key }
  end

  def upload_params
    object_params.merge(upload_id: session.fetch('upload_id'))
  end

  def expected_size(number)
    count = (blob.byte_size.to_f / PART_SIZE).ceil
    raise InvalidUpload, 'Invalid part number' unless number.between?(1, count)

    [PART_SIZE, blob.byte_size - ((number - 1) * PART_SIZE)].min
  end

  def active!
    raise InvalidUpload, 'Upload is no longer active' unless session['state'] == 'pending' && Time.iso8601(session['expires_at']).future?
  end

  def part_url(number, checksum)
    active!
    raise InvalidUpload, 'Invalid part checksum' unless Base64.strict_decode64(checksum).bytesize == 16

    signer = Aws::S3::Presigner.new(client: client)
    signer.presigned_url(:upload_part, **upload_params, part_number: number,
                                                        content_length: expected_size(number), content_md5: checksum, expires_in: 3600)
  rescue ArgumentError
    raise InvalidUpload, 'Invalid part checksum'
  end

  def upload_part(number, file, checksum)
    active!
    raise InvalidUpload, 'Invalid part size' unless file && file.size == expected_size(number)

    client.upload_part(**upload_params, part_number: number, body: file.tempfile,
                                        content_length: file.size, content_md5: checksum)
  end

  def complete!
    blob.with_lock do
      next blob if session['state'] == 'complete'

      active!
      complete_storage!
      head = client.head_object(**object_params)
      unless head.content_length == blob.byte_size && head.metadata['chatwoot-blob-id'] == blob.id.to_s
        raise InvalidUpload, 'Completed object does not match the upload'
      end

      blob.update!(metadata: blob.metadata.deep_merge('multipart' => { 'state' => 'complete' }))
      blob
    end
  end

  def abort!
    blob.with_lock do
      next if session['state'] == 'complete'

      begin
        client.abort_multipart_upload(**upload_params) if session['upload_id']
      rescue Aws::S3::Errors::NoSuchUpload
        # Already aborted, or completion succeeded before its database commit.
      end
      # Also cleans an object completed remotely but never exposed as attachable.
      client.delete_object(**object_params)
      blob.destroy!
    end
  end

  private

  def complete_storage!
    parts = client.list_parts(**upload_params).flat_map(&:parts).sort_by(&:part_number)
    validate_parts!(parts)
    client.complete_multipart_upload(**upload_params, multipart_upload: {
                                       parts: parts.map { |part| { part_number: part.part_number, etag: part.etag } }
                                     })
  rescue Aws::S3::Errors::NoSuchUpload
    # A prior completion may have succeeded despite losing its response. The
    # caller verifies the private object's identity and size before accepting it.
    nil
  end

  def validate_parts!(parts)
    expected = (blob.byte_size.to_f / PART_SIZE).ceil
    valid = parts.length == expected && parts.each_with_index.all? do |part, index|
      part.part_number == index + 1 && part.size == expected_size(index + 1)
    end
    raise InvalidUpload, 'Missing or invalid upload parts' unless valid
  end
end
