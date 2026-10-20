# Reuse the provider parsers/downloaders, but never the live-message lifecycle.
class Whatsapp::HistoryMessageService < Whatsapp::IncomingMessageWhatsappCloudService
  class Incomplete < StandardError; end

  HISTORY_STATUSES = { 'SENT' => 'sent', 'DELIVERED' => 'delivered', 'READ' => 'read', 'PLAYED' => 'read',
                       'PENDING' => 'progress', 'ERROR' => 'failed' }.freeze

  def perform
    processed_params
    lock_message_source_id!
    return reconcile_history_message(@message) if find_message_by_source_id(messages_data.first[:id])

    raise Incomplete, 'Unsupported historical message' unless Whatsapp::UnifiedMessageIngestionService::SUPPORTED.include?(message_type)

    Whatsapp::MessageIdentityObservationService.new(inbox: inbox, value: processed_params, outgoing_echo: outgoing_echo).perform
    require_correlation_identity!

    result = Whatsapp::UnifiedMessageIngestionService.new(inbox: inbox, value: processed_params, historical: true).perform do |ingestion|
      @unified_ingestion = ingestion
      import_message
    end
    apply_history_status(result)
  ensure
    @message_dedup_lock&.release!
  end

  private

  def reconcile_history_message(message)
    peer = outgoing_echo ? messages_data.first[:to] : messages_data.first[:from]
    expected_direction = outgoing_echo ? 'outgoing' : 'incoming'
    unless history_contact_matches?(message.conversation.contact, peer) && message.message_type == expected_direction &&
           !message.private? && !message.conversation.group?
      raise Whatsapp::HistoryContactResolver::Pending, 'Existing historical message participant mismatch'
    end

    apply_history_status(message)
  end

  def history_contact_matches?(contact, peer)
    return false if peer.blank?

    variants = Whatsapp::ContactIdentityLock.phone_variants(peer)
    contact.bsuid == peer || contact.contact_inboxes.exists?(inbox_id: inbox.id, source_id: variants + [peer]) ||
      variants.include?(contact.phone_number.to_s.delete_prefix('+'))
  end

  def require_correlation_identity!
    return unless WhatsappInboxLink.for_inbox(inbox)

    identity = WhatsappMessageIdentity.find_by(inbox: inbox, account_id: inbox.account_id, external_id: messages_data.first[:id])
    raise Whatsapp::HistoryContactResolver::Pending, 'Original correlation ID pending' if identity&.provider_message_id.blank?
  end

  def import_message
    ActiveRecord::Base.transaction(requires_new: true) do
      set_history_contact
      set_history_conversation
      process_in_reply_to(messages_data.first)
      message_type == 'contacts' ? create_unified_contact_message(messages_data.first) : create_regular_message(messages_data.first)
      @message_dedup_lock.ensure_owned!
      @unified_ingestion&.ensure_owned!
      @message
    end
  end

  def set_history_contact
    @message_type = outgoing_echo ? :outgoing : :incoming
    peer = outgoing_echo ? messages_data.first[:to] : messages_data.first[:from]
    @contact_inbox = @unified_ingestion&.resolved_contact_link || Whatsapp::HistoryContactResolver.new(
      inbox: inbox, peer: peer, message: messages_data.first
    ).perform
    @contact = @contact_inbox.contact
    @sender = outgoing_echo ? nil : @contact
  end

  def set_history_conversation
    target = @unified_ingestion ? @unified_ingestion.link.primary_inbox : inbox
    target.with_lock do
      @conversation = target.conversations.non_group_conversations.where(contact: @contact).order(id: :desc).first
      next if @conversation

      contact_link = target.contact_inboxes.find_by(contact: @contact) || target.contact_inboxes.create!(
        contact: @contact, source_id: @contact_inbox.source_id
      )
      timestamp = Time.zone.at(messages_data.first[:timestamp].to_i)
      @conversation = target.conversations.create!(
        account_id: target.account_id, contact: @contact, contact_inbox: contact_link, status: :resolved,
        historical_import: true, created_at: timestamp, last_activity_at: timestamp,
        agent_last_seen_at: Time.current, channel_agent_last_seen_at: Time.current
      )
    end
  end

  def create_message(...)
    super.tap do |message|
      message.historical_import = true
      message.content_attributes = message.content_attributes.merge('whatsapp_history_import' => true)
      message.created_at = Time.zone.at(messages_data.first[:timestamp].to_i)
      status = HISTORY_STATUSES[messages_data.first.dig(:history_context, :status).to_s.upcase]
      message.status = status if outgoing_echo && status
    end
  end

  def attach_files
    unless %w[text location contacts].include?(message_type) || messages_data.first.dig(message_type, :id).present?
      raise Incomplete, 'Historical media ID unavailable'
    end

    super
    return if %w[text location contacts].include?(message_type) || @message.attachments.any?

    raise Incomplete, 'Historical media is not available yet'
  end

  # A shared card is content, not evidence to rename another saved contact.
  def update_shared_contact_name(*)
    nil
  end

  def apply_history_status(message)
    return message unless message&.outgoing?

    status = HISTORY_STATUSES[messages_data.first.dig(:history_context, :status).to_s.upcase]
    order = %w[progress failed sent delivered read]
    return message unless status

    message.with_lock do
      next unless order.index(status) > order.index(message.status).to_i

      # Historical receipts must never dispatch message.updated to agent bots.
      message.update_columns(status: Message.statuses.fetch(status), updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end
    message
  end
end
