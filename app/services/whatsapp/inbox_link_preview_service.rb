class Whatsapp::InboxLinkPreviewService
  def initialize(link:)
    @link = link
  end

  def perform
    rows = conversation_rows
    active = active_conversations(rows)
    fingerprint = Digest::SHA256.hexdigest([configuration, rows].to_json)
    {
      conflicts: conflicts_for(active), active_conversations: active, active_conversations_count: active.size,
      confirmation_required: active.any?, historical_merge: false, cutoff: @link.activated_at,
      confirmation: verifier.generate(fingerprint, expires_in: 15.minutes, purpose: 'whatsapp_inbox_link')
    }
  end

  def confirmed?(token, preview)
    expected = verifier.verified(preview[:confirmation], purpose: 'whatsapp_inbox_link')
    supplied = verifier.verified(token.to_s, purpose: 'whatsapp_inbox_link')
    supplied.present? && supplied == expected
  end

  private

  def conversation_rows
    Conversation.where(account_id: @link.account_id, inbox_id: [@link.primary_inbox_id, @link.secondary_inbox_id])
                .where.not(status: Conversation.statuses.fetch('resolved')).order(:id)
                .pluck(:id, :display_id, :inbox_id, :contact_id, :status, :updated_at)
  end

  def active_conversations(rows)
    keys = %i[id display_id inbox_id contact_id status]
    rows.map { |row| keys.zip(row.first(5)).to_h }
  end

  def conflicts_for(active)
    active.group_by { |row| row[:contact_id] }.filter_map do |contact_id, conversations|
      next unless conversations.size > 1

      { contact_id: contact_id, conversation_ids: conversations.pluck(:id), resolution: 'manual_review_required' }
    end
  end

  def configuration
    [@link.id, @link.account_id, @link.primary_inbox_id, @link.secondary_inbox_id, @link.default_provider, @link.enabled,
     @link.meta_initial_messages_enabled, @link.meta_initial_messages_limit]
  end

  def verifier
    Rails.application.message_verifier('whatsapp_inbox_link_preview')
  end
end
