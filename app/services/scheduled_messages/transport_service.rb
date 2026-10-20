# Captures intent before dispatch. The selected provider and each effective
# executor survive default-provider changes, client age and sequence delays.
class ScheduledMessages::TransportService
  def initialize(schedule)
    @schedule = schedule
  end

  def capture!(requested_provider: nil)
    validate_requested_provider!(requested_provider)
    link = current_link
    if snapshot.present? && requested_provider.nil?
      validate_snapshot!(link)
      authorize_sender!(link)
      capture_items!(link)
      return
    end
    return if link.nil? && requested_provider.nil?

    capture_selection!(link, requested_provider)
  end

  def validate!
    capture! if snapshot.empty?
    return if snapshot.empty?

    link = current_link
    validate_snapshot!(link)
    authorize_sender!(link)
    capture_items!(link)
  end

  def canonical_inbox
    return @schedule.inbox if snapshot.empty?

    link = current_link
    validate_snapshot!(link)
    link.primary_inbox
  end

  def requested_provider
    snapshot['requested_provider']
  end

  def validate_message!(item, message)
    return if snapshot.empty?

    expected = item.whatsapp_transport.to_h
    actual = message.content_attributes.to_h['whatsapp_transport'].to_h
    reject!(:executor_changed) unless expected.present? && expected == actual && message.inbox_id == canonical_inbox.id
    validate_snapshot!(current_link)
  end

  private

  def capture_selection!(link, requested_provider)
    reject!(:link_changed) unless link
    authorize_sender!(link)
    requested = requested_provider || @schedule.inbox.channel.provider
    selection = requested_provider ? 'explicit' : 'legacy_inbox'
    if dispatched_items.exists?
      # An administrative edit cannot make a partial/uncertain sequence into a
      # fresh send. Existing receipts remain attached to their original rows.
      reject!(:already_dispatched) if requested_provider.present?
      validate_dispatched_evidence!(link, requested)
    end
    # Due legacy schedules must capture intent before changing state. Updating
    # only this internally constructed snapshot avoids the future-date validator
    # rejecting a schedule that is correctly being dispatched now.
    metadata = {
      'link_id' => link.id, 'activation_cutoff' => link.activated_at.iso8601(6),
      'requested_provider' => requested, 'inbox_id' => link.inbox_for(requested).id, 'selection_source' => selection
    }
    @schedule.update_columns(whatsapp_transport: metadata, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    capture_items!(link, replace: requested_provider.present?)
  end

  def snapshot
    @schedule.whatsapp_transport.to_h
  end

  def current_link
    return if @schedule.conversation.group?

    WhatsappInboxLink.for_inbox(@schedule.inbox)
  end

  def dispatched_items
    @schedule.items.where.not(message_id: nil).or(@schedule.items.where.not(dispatched_at: nil))
             .or(@schedule.items.where(status: %i[dispatching sent]))
  end

  def validate_requested_provider!(provider)
    return if provider.nil? || (provider.is_a?(String) && WhatsappInboxLink::PROVIDERS.include?(provider))

    reject!(:invalid_provider)
  end

  def validate_snapshot!(link)
    selected = link&.inbox_for(snapshot['requested_provider'])
    reject!(:link_changed) unless link && selected
    expected = { 'link_id' => link.id, 'inbox_id' => selected.id, 'activation_cutoff' => link.activated_at.iso8601(6) }
    valid = snapshot.slice(*expected.keys) == expected && link.account_id == @schedule.account_id
    reject!(:link_changed) unless valid
  end

  def authorize_sender!(link)
    membership = @schedule.account.account_users.find_by(user_id: @schedule.sender_id)
    reject!(:sender_unavailable) unless membership

    reject!(:sender_unavailable) unless sender_has_access?(membership, link.primary_inbox_id)
  end

  def sender_has_access?(membership, inbox_id)
    previous = [Current.user, Current.account, Current.account_user]
    Current.user = @schedule.sender
    Current.account = @schedule.account
    Current.account_user = membership
    context = { user: Current.user, account: Current.account, account_user: membership }
    Pundit.policy_scope!(context, Inbox).exists?(id: inbox_id)
  ensure
    Current.user, Current.account, Current.account_user = previous
  end

  def validate_dispatched_evidence!(link, requested)
    dispatched_items.includes(:message).find_each do |item|
      metadata = item.message&.content_attributes&.dig('whatsapp_transport').to_h
      next if legacy_dispatched_evidence?(item, metadata, link)
      next if metadata.slice('link_id', 'requested_provider', 'activation_cutoff') == {
        'link_id' => link.id, 'requested_provider' => requested, 'activation_cutoff' => link.activated_at.iso8601(6)
      }

      reject!(:already_dispatched)
    end
  end

  def legacy_dispatched_evidence?(item, metadata, link)
    metadata.empty? && item.message&.inbox_id == @schedule.inbox_id && @schedule.created_at < link.activated_at
  end

  def capture_items!(link, replace: false)
    @schedule.items.each do |item|
      next if item.message_id || item.dispatched_at

      capture_item!(link, item, replace)
    end
  end

  def capture_item!(link, item, replace)
    message = Message.new(account: @schedule.account, inbox: link.primary_inbox, conversation: @schedule.conversation,
                          message_type: :outgoing, private: false, content_type: item.content_type, content_attributes: item.content_attributes)
    Whatsapp::UnifiedTransportService.prepare!(message: message, requested_provider: requested_provider)
    metadata = message.content_attributes.fetch('whatsapp_transport')
    reject!(:executor_changed) if !replace && item.whatsapp_transport.present? && item.whatsapp_transport != metadata
    item.update!(whatsapp_transport: metadata) if item.whatsapp_transport != metadata
  end

  def reject!(reason)
    raise ArgumentError, I18n.t("scheduled_messages.transport_errors.#{reason}")
  end
end

ScheduledMessages::TransportService.prepend_mod_with('ScheduledMessages::TransportService')
