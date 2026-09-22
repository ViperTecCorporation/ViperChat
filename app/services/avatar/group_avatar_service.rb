# A group may have several legacy has_one attachments. Never purge those blobs
# while choosing or replacing its photo: keep old links under archival names.
class Avatar::GroupAvatarService
  def self.group_source_id(contact)
    return unless contact.is_a?(Contact)

    sources = contact.contact_inboxes.distinct.pluck(:source_id)
    sources.sole if sources.one? && sources.first.to_s.end_with?('@g.us')
  end

  def initialize(contact, group_source_id: nil)
    @contact = contact
    @group_source_id = group_source_id || self.class.group_source_id(contact)
  end

  def preferred_attachment
    return unless @group_source_id

    attachments.find { |attachment| manual?(attachment) || group_photo?(attachment) }
  end

  def avatar_url
    attachment = preferred_attachment
    return unless attachment&.blob&.representable?

    Rails.application.routes.url_helpers.url_for(attachment.blob.representation(resize_to_fill: [250, nil]))
  end

  def replace
    return yield unless @group_source_id

    @contact.with_lock do
      archive_except(nil)
      reset_avatar
      yield
    end
  end

  def plan
    return { status: 'ambiguous_contact' } unless @group_source_id

    avatars = attachments
    return { status: 'no_duplicates' } unless avatars.many?
    return { status: 'manual_photo_present' } if avatars.any? { |attachment| manual?(attachment) }

    selection_plan(avatars)
  end

  def selection_plan(avatars)
    selected = avatars.find { |attachment| group_photo?(attachment, allow_opaque: false) }
    return { status: 'no_verified_group_photo' } unless selected

    { status: 'ready', keep_id: selected.id, archive_ids: avatars.map(&:id) - [selected.id] }
  end

  def repair!(backup:)
    @contact.with_lock do
      current = plan
      next current unless current[:status] == 'ready'

      backup.puts({ contact_id: @contact.id, account_id: @contact.account_id, plan: current,
                    attachments: attachments.map(&:attributes) }.to_json)
      backup.flush
      backup.fsync
      archive_except(current[:keep_id])
      reset_avatar
      current.merge(applied: true)
    end
  end

  private

  def attachments
    ActiveStorage::Attachment.where(record: @contact, name: 'avatar').includes(:blob).order(created_at: :desc, id: :desc).to_a
  end

  def manual?(attachment)
    !attachment.blob.filename.to_s.start_with?('unoapi-profile-')
  end

  def group_photo?(attachment, allow_opaque: true)
    identities = [@group_source_id]
    identity = @contact.additional_attributes['unoapi_profile_picture_id'].to_s
    identities << identity if allow_opaque && identity.present? && identity.exclude?('@')
    identities.any? do |id|
      attachment.blob.filename.to_s.start_with?("unoapi-profile-#{Digest::SHA256.hexdigest(id)[0, 12]}.")
    end
  end

  def archive_except(keep_id)
    attachments.each do |attachment|
      next if attachment.id == keep_id

      attachment.update!(name: "group_avatar_history_#{attachment.id}")
    end
  end

  def reset_avatar
    @contact.association(:avatar_attachment).reset
    @contact.association(:avatar_blob).reset
  end
end
