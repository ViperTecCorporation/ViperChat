module Whatsapp::AvatarMetadata
  KEYS = %i[
    avatar_hash content_length content_md5 content_type etag file_hash file_size
    hash last_modified picture_hash profile_picture_hash size updated_at
  ].freeze

  private

  def avatar_metadata_from(*sources)
    Array(sources).compact.each_with_object({}) do |source, result|
      next unless source.respond_to?(:with_indifferent_access)

      attrs = source.with_indifferent_access
      [attrs[:picture_metadata], attrs[:profile_picture_metadata], attrs[:group_picture_metadata]].compact.each do |metadata|
        result.merge!(avatar_metadata_from(metadata))
      end
      KEYS.each do |key|
        value = avatar_metadata_value(attrs, key)
        result[key] = value if value.present?
      end
    end
  end

  def avatar_metadata_value(attrs, key)
    attrs[key].presence || attrs[:"picture_#{key}"].presence || attrs[:"profile_picture_#{key}"].presence
  end
end
