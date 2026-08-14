class Avatar::AvatarFromUnoapiJob < ApplicationJob
  queue_as :purgable

  def self.enqueue_if_needed(contact, channel, picture_id, avatar_metadata = nil, fallback_url = nil)
    return false if contact.blank? || channel.blank? || picture_id.blank?

    signature = signature_for(channel, picture_id, avatar_metadata)
    reserved = contact.with_lock do
      attrs = contact.additional_attributes || {}
      next false if [attrs['unoapi_avatar_signature'], attrs['unoapi_avatar_enqueued_signature']].include?(signature)

      attrs['unoapi_avatar_enqueued_signature'] = signature
      contact.update_columns(additional_attributes: attrs) # rubocop:disable Rails/SkipsModelValidations
      true
    end
    return false unless reserved

    options = {
      'avatar_metadata' => normalized_metadata(avatar_metadata).presence,
      'fallback_url' => fallback_url.presence,
      'signature' => signature
    }.compact
    perform_later(contact, channel, picture_id.to_s, options)
    true
  end

  def self.signature_for(channel, picture_id, avatar_metadata)
    Digest::SHA256.hexdigest([channel.id, picture_id, normalized_metadata(avatar_metadata).to_json].join('|'))
  end

  def self.normalized_metadata(avatar_metadata)
    Avatar::AvatarFromUrlJob.filtered_avatar_metadata(avatar_metadata)
  end

  def perform(contact, channel, picture_id, options = {})
    return unless channel.is_a?(Channel::Whatsapp) && channel.provider == 'unoapi'

    options = options.with_indifferent_access
    result = Whatsapp::Unoapi::ProfilePictureClient.new(channel).fetch(picture_id)
    attach_avatar(contact, result, picture_id)
    mark_synced(contact, picture_id, options[:avatar_metadata], options[:signature])
  rescue Whatsapp::Unoapi::ProfilePictureClient::NotFoundError
    enqueue_fallback(contact, options)
    release_reservation(contact, options[:signature])
  rescue Whatsapp::Unoapi::ProfilePictureClient::AuthenticationError,
         Whatsapp::Unoapi::ProfilePictureClient::InvalidResponseError => e
    release_reservation(contact, options[:signature])
    Rails.logger.error("AvatarFromUnoapiJob: #{e.class} - #{e.message}")
  rescue Whatsapp::Unoapi::ProfilePictureClient::TransientError
    release_reservation(contact, options[:signature])
    raise
  end

  private

  def attach_avatar(contact, result, picture_id)
    contact.avatar.attach(
      io: StringIO.new(result.body),
      filename: "unoapi-profile-#{Digest::SHA256.hexdigest(picture_id)[0, 12]}#{extension_for(result.content_type)}",
      content_type: result.content_type
    )
  end

  def extension_for(content_type)
    {
      'image/jpeg' => '.jpg',
      'image/png' => '.png',
      'image/gif' => '.gif',
      'image/webp' => '.webp'
    }.fetch(content_type, '')
  end

  def enqueue_fallback(contact, options)
    fallback_url = options[:fallback_url]
    return if fallback_url.blank?

    Avatar::AvatarFromUrlJob.enqueue_if_needed(contact, fallback_url, self.class.normalized_metadata(options[:avatar_metadata]))
  end

  def mark_synced(contact, picture_id, avatar_metadata, signature)
    contact.with_lock do
      attrs = contact.additional_attributes || {}
      attrs['unoapi_avatar_signature'] = signature
      attrs['unoapi_profile_picture_id'] = picture_id
      attrs['unoapi_profile_picture_metadata'] = avatar_metadata if avatar_metadata.present?
      attrs['last_unoapi_avatar_sync_at'] = Time.current.iso8601
      attrs.delete('unoapi_avatar_enqueued_signature') if attrs['unoapi_avatar_enqueued_signature'] == signature
      contact.update_columns(additional_attributes: attrs) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def release_reservation(contact, signature)
    return if signature.blank?

    contact.with_lock do
      attrs = contact.additional_attributes || {}
      next unless attrs['unoapi_avatar_enqueued_signature'] == signature

      attrs.delete('unoapi_avatar_enqueued_signature')
      contact.update_columns(additional_attributes: attrs) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
