# Downloads and attaches avatar images from a URL.
# Notes:
# - For contact objects, we use `additional_attributes` to rate limit the
#   job and track state.
# - We save the hash of the synced URL to retrigger downloads only when
#   there is a change in the underlying asset.
# - A 1 minute rate limit window is enforced via `last_avatar_sync_at`.
class Avatar::AvatarFromUrlJob < ApplicationJob
  include UrlHelper
  queue_as :purgable

  ALLOWED_CONTENT_TYPES = Avatarable::ALLOWED_AVATAR_CONTENT_TYPES
  MAX_DOWNLOAD_SIZE = 15.megabytes
  RATE_LIMIT_WINDOW = 1.minute
  AVATAR_METADATA_KEYS = %w[
    avatar_hash content_length content_md5 content_type etag file_hash file_size
    hash last_modified picture_hash profile_picture_hash size updated_at
  ].freeze

  def self.should_enqueue?(avatarable, avatar_url, avatar_metadata = nil)
    return false if avatar_url.blank?
    return true unless avatarable.is_a?(Contact)

    attrs = avatarable.additional_attributes || {}
    url_hash = generate_url_hash(avatar_url, avatar_signature_metadata(avatar_url, avatar_metadata))
    attrs['avatar_url_hash'] != url_hash && attrs['avatar_url_enqueued_hash'] != url_hash
  end

  def self.enqueue_if_needed(avatarable, avatar_url, avatar_metadata = nil)
    signature_metadata = avatar_signature_metadata(avatar_url, avatar_metadata)
    return false unless reserve_enqueue!(avatarable, avatar_url, signature_metadata)

    job_args = [avatarable, avatar_url]
    job_args << signature_metadata if signature_metadata.present?
    perform_later(*job_args)
    true
  end

  def self.reserve_enqueue!(avatarable, avatar_url, avatar_metadata = nil)
    return false if avatar_url.blank?
    return true unless avatarable.is_a?(Contact)

    avatarable.with_lock do
      attrs = avatarable.additional_attributes || {}
      url_hash = generate_url_hash(avatar_url, avatar_metadata)
      return false if attrs['avatar_url_hash'] == url_hash || attrs['avatar_url_enqueued_hash'] == url_hash

      attrs['avatar_url_enqueued_hash'] = url_hash
      attrs['avatar_url_signature_metadata'] = avatar_metadata if avatar_metadata.present?
      attrs['last_avatar_enqueue_at'] = Time.current.iso8601
      avatarable.update_columns(additional_attributes: attrs) # rubocop:disable Rails/SkipsModelValidations
      true
    end
  end

  def self.generate_url_hash(url, avatar_metadata = nil)
    signature_parts = [normalized_avatar_url(url)]
    normalized_metadata = normalized_avatar_metadata(avatar_metadata)
    signature_parts << normalized_metadata.to_json if normalized_metadata.present?

    Digest::SHA256.hexdigest(signature_parts.join('|'))
  end

  def self.normalized_avatar_url(url)
    uri = URI.parse(url.to_s)
    uri.query = nil
    uri.fragment = nil
    uri.to_s
  rescue URI::InvalidURIError
    url.to_s
  end

  def self.avatar_signature_metadata(avatar_url, avatar_metadata = nil)
    normalized_avatar_metadata(avatar_metadata).presence || remote_avatar_metadata(avatar_url)
  end

  def self.normalized_avatar_metadata(avatar_metadata)
    attrs = avatar_metadata.to_h.with_indifferent_access
    AVATAR_METADATA_KEYS.each_with_object({}) do |key, result|
      value = attrs[key].presence
      result[key] = value.to_s if value.present?
    end
  rescue StandardError
    {}
  end

  def self.remote_avatar_metadata(avatar_url)
    options = SafeFetch::RequestOptions.new(
      url: avatar_url,
      method: :get,
      headers: { 'Range' => 'bytes=0-0' },
      validate_content_type: false,
      allowed_content_type_prefixes: [],
      allowed_content_types: []
    )
    response = if SafeFetch.allow_private_network?
                 SafeFetch::PrivateNetworkRequest.new(options).perform
               else
                 SsrfFilter.head(options.url, **options.request_options)
               end

    return {} unless response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPRedirection)

    {
      'etag' => response['etag'],
      'last_modified' => response['last-modified'],
      'content_length' => range_content_length(response['content-range']) || response['content-length'],
      'content_type' => response['content-type']
    }.compact
  rescue StandardError => e
    Rails.logger.debug { "AvatarFromUrlJob: avatar metadata lookup skipped for #{avatar_url}: #{e.class} - #{e.message}" }
    {}
  end

  def self.range_content_length(content_range)
    content_range.to_s.split('/').last.presence
  end

  def perform(avatarable, avatar_url, avatar_metadata = nil)
    return if duplicate_avatar_url?(avatarable, avatar_url, avatar_metadata)

    begin
      return unless syncable_avatar?(avatarable, avatar_url, avatar_metadata)

      fetch_and_attach_avatar(avatarable, avatar_url)
    rescue SafeFetch::HttpError => e
      log_http_error(avatar_url, e)
    rescue SafeFetch::Error => e
      Rails.logger.error "AvatarFromUrlJob error for #{avatar_url}: #{e.class} - #{e.message}"
    ensure
      update_avatar_sync_attributes(avatarable, avatar_url, avatar_metadata)
    end
  end

  private

  def duplicate_avatar_url?(avatarable, avatar_url, avatar_metadata)
    return false if avatar_url.blank?
    return false unless avatarable.is_a?(Contact)

    duplicate_url?(avatarable.additional_attributes || {}, avatar_url, avatar_metadata)
  end

  def syncable_avatar?(avatarable, avatar_url, avatar_metadata)
    avatarable.respond_to?(:avatar) &&
      url_valid?(avatar_url) &&
      should_sync_avatar?(avatarable, avatar_url, avatar_metadata)
  end

  def fetch_and_attach_avatar(avatarable, avatar_url)
    SafeFetch.fetch(
      avatar_url,
      max_bytes: MAX_DOWNLOAD_SIZE,
      allowed_content_type_prefixes: [],
      allowed_content_types: ALLOWED_CONTENT_TYPES
    ) do |avatar_file|
      attach_avatar(avatarable, avatar_file)
    end
  end

  def attach_avatar(avatarable, avatar_file)
    raise SafeFetch::FetchError, 'Invalid file' unless valid_file?(avatar_file)

    avatarable.avatar.attach(
      io: avatar_file.tempfile,
      filename: avatar_file.original_filename,
      content_type: avatar_file.content_type
    )
  end

  def log_http_error(avatar_url, error)
    if error.message.start_with?('404')
      Rails.logger.info "AvatarFromUrlJob: avatar not found at #{avatar_url}"
    else
      Rails.logger.error "AvatarFromUrlJob error for #{avatar_url}: #{error.class} - #{error.message}"
    end
  end

  def should_sync_avatar?(avatarable, avatar_url, avatar_metadata)
    # Only Contacts are rate-limited and hash-gated.
    return true unless avatarable.is_a?(Contact)

    attrs = avatarable.additional_attributes || {}

    return false if within_rate_limit?(attrs)
    return false if duplicate_url?(attrs, avatar_url, avatar_metadata)

    true
  end

  def within_rate_limit?(attrs)
    ts = attrs['last_avatar_sync_at']
    return false if ts.blank?

    Time.zone.parse(ts) > RATE_LIMIT_WINDOW.ago
  end

  def duplicate_url?(attrs, avatar_url, avatar_metadata)
    stored_hash = attrs['avatar_url_hash']
    stored_hash.present? && stored_hash == generate_url_hash(avatar_url, avatar_metadata)
  end

  def generate_url_hash(url, avatar_metadata = nil)
    self.class.generate_url_hash(url, avatar_metadata)
  end

  def update_avatar_sync_attributes(avatarable, avatar_url, avatar_metadata)
    # Only Contacts have sync attributes persisted
    return unless avatarable.is_a?(Contact)
    return if avatar_url.blank?

    additional_attributes = avatarable.additional_attributes || {}
    additional_attributes['last_avatar_sync_at'] = Time.current.iso8601
    additional_attributes['avatar_url_hash'] = generate_url_hash(avatar_url, avatar_metadata)
    additional_attributes['avatar_url_signature_metadata'] = avatar_metadata if avatar_metadata.present?
    additional_attributes.delete('avatar_url_enqueued_hash')

    # Persist without triggering validations that may fail due to avatar file checks
    avatarable.update_columns(additional_attributes: additional_attributes) # rubocop:disable Rails/SkipsModelValidations
  end

  def valid_file?(file)
    return false if file.original_filename.blank?

    true
  end
end
