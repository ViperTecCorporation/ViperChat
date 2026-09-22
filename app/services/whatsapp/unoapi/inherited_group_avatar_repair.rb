# Repairs only authenticated participant photos mistakenly stored on group contacts.
# The attachment is archived, not purged, so its original blob remains recoverable.
class Whatsapp::Unoapi::InheritedGroupAvatarRepair
  BACKUP_KEY = 'unoapi_inherited_avatar_backup'.freeze
  AVATAR_KEYS = %w[unoapi_avatar_signature unoapi_avatar_enqueued_signature unoapi_profile_picture_id
                   unoapi_profile_picture_metadata last_unoapi_avatar_sync_at].freeze

  def initialize(conversation)
    @conversation = conversation
    @contact = conversation.contact
  end

  def perform(apply: false)
    @contact.with_lock do
      @conversation.reload
      next false unless contaminated?
      next true unless apply

      archive_avatar
      true
    end
  end

  private

  def contaminated?
    @picture_id = @contact.additional_attributes['unoapi_profile_picture_id'].to_s
    return false unless @picture_id.end_with?('@lid', '@s.whatsapp.net', '@c.us')
    return false if @contact.additional_attributes.key?(BACKUP_KEY)
    return false unless group_only_contact? && matching_conversations?

    generated_participant_avatar? && participant_has_same_image?
  end

  def generated_participant_avatar?
    @attachment = @contact.avatar_attachment
    return false unless @attachment

    @attachment.blob.filename.to_s.start_with?("unoapi-profile-#{Digest::SHA256.hexdigest(@picture_id)[0, 12]}.")
  end

  def group_only_contact?
    return false unless @conversation.group? && @conversation.inbox.channel.try(:provider) == 'unoapi'

    sources = @contact.contact_inboxes.pluck(:source_id)
    sources.present? && sources.all? { |source| source.to_s.end_with?('@g.us') }
  end

  def matching_conversations?
    @conversations = @contact.conversations.lock.to_a
    @conversations.present? && @conversations.all? do |conversation|
      attrs = conversation.additional_attributes
      conversation.group? && attrs['group_picture'].blank? && attrs['group_picture_id'] == @picture_id
    end
  end

  def participant_has_same_image?
    participant_ids = ContactInbox.where(inbox_id: @conversation.inbox_id, source_id: @picture_id)
                                  .where.not(contact_id: @contact.id).select(:contact_id)
    ActiveStorage::Attachment.joins(:blob).where(record_type: 'Contact', name: 'avatar', record_id: participant_ids)
                             .exists?(active_storage_blobs: { checksum: @attachment.blob.checksum })
  end

  def archive_avatar
    attrs = @contact.additional_attributes.deep_dup
    attrs[BACKUP_KEY] = {
      'attachment_id' => @attachment.id, 'blob_id' => @attachment.blob_id,
      'avatar_metadata' => attrs.slice(*AVATAR_KEYS),
      'conversations' => @conversations.to_h { |conversation| [conversation.id.to_s, conversation.additional_attributes.deep_dup] },
      'repaired_at' => Time.current.iso8601
    }
    attrs.except!(*AVATAR_KEYS)
    @attachment.update!(name: BACKUP_KEY)
    @contact.update!(additional_attributes: attrs)
    @conversations.each do |conversation|
      conversation.update!(additional_attributes: conversation.additional_attributes.except('group_picture_id'))
    end
  end
end
