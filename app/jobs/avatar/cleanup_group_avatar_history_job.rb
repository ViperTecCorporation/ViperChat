class Avatar::CleanupGroupAvatarHistoryJob < ApplicationJob
  queue_as :purgable

  def perform(contact_id)
    contact = Contact.find_by(id: contact_id)
    return unless contact

    contact.with_lock do
      current = Avatar::GroupAvatarService.new(contact).preferred_attachment
      # Keep the recovery copy if the replacement was never uploaded or is missing.
      next unless current && current.blob.service.exist?(current.blob.key)

      history = ActiveStorage::Attachment.where(record: contact).where("name LIKE 'group_avatar_history_%'")
      history.find_each do |attachment|
        next unless attachment.name == "group_avatar_history_#{attachment.id}"

        # Active Storage only purges an unreferenced blob, preserving shared files.
        attachment.purge_later
      end
    end
  end
end
