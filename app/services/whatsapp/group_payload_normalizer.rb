class Whatsapp::GroupPayloadNormalizer
  pattr_initialize [:processed_params!, :inbox!]

  AVATAR_METADATA_KEYS = %i[
    avatar_hash content_length content_md5 content_type etag file_hash file_size
    hash last_modified picture_hash profile_picture_hash size updated_at
  ].freeze

  def perform
    return { group: false } if group_source_id.blank?

    {
      group: true,
      group_source_id: group_source_id,
      group_title: contact[:group_subject].presence || group_source_id,
      group_picture: contact[:group_picture].presence,
      group_picture_metadata: avatar_metadata_from(contact),
      sender_identifier: sender_identifier,
      sender_phone: sender_phone,
      sender_bsuid: sender_bsuid,
      sender_username: sender_username,
      sender_name: sender_name,
      sender_picture: contact.dig(:profile, :picture).presence,
      sender_picture_metadata: avatar_metadata_from(contact, contact[:profile]),
      message_source_id: message[:id],
      message_from: message[:from]
    }
  end

  private

  def message
    @message ||= processed_params[:messages]&.first || {}
  end

  def contact
    @contact ||= processed_params[:contacts]&.first || {}
  end

  def avatar_metadata_from(*sources)
    Array(sources).compact.each_with_object({}) do |source, result|
      next unless source.respond_to?(:with_indifferent_access)

      attrs = source.with_indifferent_access
      [attrs[:picture_metadata], attrs[:profile_picture_metadata], attrs[:group_picture_metadata]].compact.each do |metadata|
        result.merge!(avatar_metadata_from(metadata))
      end
      AVATAR_METADATA_KEYS.each do |key|
        value = attrs[key].presence || attrs[:"picture_#{key}"].presence || attrs[:"profile_picture_#{key}"].presence
        result[key] = value if value.present?
      end
    end
  end

  def group_source_id
    @group_source_id ||= normalize_group_id(message[:group_id].presence || contact[:group_id])
  end

  def sender_identifier
    sender_bsuid.presence || sender_phone
  end

  def sender_phone
    raw_phone = message[:from].presence || contact[:wa_id]
    return if raw_phone.to_s.include?('@lid')

    digits = raw_phone.to_s.gsub(/\D/, '')
    return if digits.blank? || digits == '0'
    return unless digits.match?(/^[1-9]\d{7,14}$/)

    digits
  end

  def sender_bsuid
    message[:from_user_id].presence || contact[:user_id].presence
  end

  def sender_username
    contact.dig(:profile, :username).presence
  end

  def sender_name
    contact.dig(:profile, :name).presence ||
      sender_username ||
      sender_phone ||
      sender_bsuid
  end

  def normalize_group_id(value)
    raw = value.to_s.strip
    return '' if raw.blank?
    return raw if raw.end_with?('@g.us')

    digits = raw.gsub(/\D/, '')
    digits.present? ? "#{digits}@g.us" : raw
  end
end
