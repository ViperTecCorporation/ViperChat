class Whatsapp::HistoryImportService
  def self.scope_snapshot(inbox)
    link = WhatsappInboxLink.for_inbox(inbox)
    { 'history_link_id' => link&.id, 'history_link_activation' => link&.activated_at&.iso8601(6) }
  end

  def initialize(event:)
    @event = event
    @channel = event.channel
  end

  def perform
    return unless eligible?

    @event.with_lock do
      next unless @event.state == 'pending_import' && @event.expires_at > Time.current
      next if link_scope_changed?

      import_history
    end
  end

  private

  def eligible?
    @event.field == 'history' && @event.state == 'pending_import' && @channel.account.active? &&
      @channel.provider == 'whatsapp_cloud' && !@channel.reauthorization_required?
  end

  def link_scope_changed?
    return false unless @event.details.key?('history_link_id')

    link = WhatsappInboxLink.for_inbox(@channel.inbox)
    @event.details['history_link_id'] != link&.id || @event.details['history_link_activation'] != link&.activated_at&.iso8601(6)
  end

  def import_history
    if @channel.reload.provider_config.fetch('ignore_history_messages', true) != false
      @event.update!(state: 'recorded', reason: 'history_ignored', payload: {})
      return
    end

    @counts = { 'imported_messages_count' => 0, 'duplicate_messages_count' => 0, 'pending_messages_count' => 0, 'failed_messages_count' => 0 }
    value = @event.payload.dig('entry', 0, 'changes', 0, 'value')
    unless supported_envelope?(value)
      @event.update!(state: 'review', reason: 'unsupported_history_format')
      return
    end
    Array(value['history']).each { |history| Array(history['threads']).each { |thread| import_thread(thread) } }
    Array(value['messages']).each { |message| import_followup(message) }
    persist_results
  end

  def supported_envelope?(value)
    value.is_a?(Hash) && (value['history'].is_a?(Array) || value['messages'].is_a?(Array))
  end

  # Meta's media follow-up has no thread and may omit `to`. Only a retained,
  # same-channel/same-link receipt can supply the missing peer and direction.
  def import_followup(message)
    return unless within_period?(message)

    contexts = retained_contexts(message['id'])
    if contexts.one?
      thread, original = contexts.first
      if followup_participants?(message, thread)
        contextual = message.except('to').merge(original.slice('from', 'to'))
        contextual['history_context'] = original.fetch('history_context', {}).merge(message.fetch('history_context', {}))
        return import_thread(thread.merge('messages' => [contextual]))
      end
    end
    fallback_thread = followup_thread(message) if contexts.empty?
    return import_thread(fallback_thread) if fallback_thread

    @counts['pending_messages_count'] += 1
  end

  def followup_participants?(message, thread)
    context_participant?(message['from'], thread) && (message['to'].blank? || context_participant?(message['to'], thread))
  end

  def context_participant?(participant, thread)
    business_sender?(participant) || same_peer?(participant, thread['id'])
  end

  def followup_thread(message)
    if business_sender?(message['from'])
      return if message['to'].blank? || business_sender?(message['to'])

      { 'id' => message['to'], 'messages' => [message] }
    elsif message['from'].present? && (message['to'].blank? || business_sender?(message['to']))
      # The documented asset example contains `from` only. An explicit business
      # recipient is also inbound, never an SMB echo just because `to` exists.
      { 'id' => message['from'], 'messages' => [message.except('to')] }
    end
  end

  def retained_contexts(id)
    return [] if id.blank?

    needle = { entry: [{ changes: [{ value: { history: [{ threads: [{ messages: [{ id: id }] }] }] } }] }] }
    receipts = WhatsappManagementEvent.where(account_id: @event.account_id, channel_id: @channel.id, field: 'history')
                                      .where('expires_at > ?', Time.current).where('payload @> ?', needle.to_json)
    receipts.flat_map do |receipt|
      next [] unless receipt.details.slice('history_link_id', 'history_link_activation') ==
                     @event.details.slice('history_link_id', 'history_link_activation')

      receipt_contexts(receipt, id)
    end.uniq
  end

  def receipt_contexts(receipt, id)
    histories = receipt.payload.dig('entry', 0, 'changes', 0, 'value', 'history')
    histories.flat_map do |history|
      Array(history['threads']).flat_map do |thread|
        Array(thread['messages']).filter_map do |original|
          next unless original['id'] == id && within_period?(original)

          [thread.slice('id', 'recipient_type'), original.slice('from', 'to', 'history_context')]
        end
      end
    end
  end

  def persist_results
    pending = @counts['pending_messages_count'].positive?
    reason = @counts['failed_messages_count'].positive? ? 'import_failed' : 'import_identity_pending' if pending
    @event.update!(state: pending ? 'pending_import' : 'processed', reason: reason, details: @event.details.merge(@counts))
  end

  def import_thread(thread)
    Array(thread['messages']).sort_by { |message| message['timestamp'].to_i }.each do |message|
      next unless within_period?(message)
      next if @channel.provider_config['ignore_group_messages'] == true && historical_group?(thread, message)

      import_item(thread, message)
    end
  end

  def within_period?(message)
    return false unless message['timestamp'].to_s.match?(/\A\d{1,12}\z/)

    time = Time.zone.at(message['timestamp'].to_i)
    days = @channel.provider_config.fetch('history_max_age_days', 7).to_i.clamp(1, 3650)
    time.between?(@event.created_at - days.days, @event.created_at)
  end

  def import_item(thread, message)
    raise Whatsapp::HistoryContactResolver::Pending, 'Historical group requires group identity proof' if historical_group?(thread, message)

    message = message.with_indifferent_access
    raise Whatsapp::HistoryContactResolver::Pending, 'Missing historical ID' if message[:id].blank?

    message = message.merge(to: thread['id']) if message[:to].blank? && business_sender?(message[:from])

    outgoing = historical_outgoing?(message)
    validate_peer!(thread['id'], message, outgoing)
    result = Whatsapp::HistoryMessageService.new(inbox: @channel.inbox, params: message_params(message, outgoing), outgoing_echo: outgoing).perform
    @counts[result_counter(result)] += 1
  rescue Whatsapp::HistoryContactResolver::Pending, Whatsapp::MessageDedupLock::Busy, Whatsapp::UnifiedMessageIngestionService::Busy
    @counts['pending_messages_count'] += 1
  rescue Whatsapp::HistoryMessageService::Incomplete, ActiveRecord::RecordInvalid, ArgumentError, Down::Error, HTTParty::Error, Timeout::Error
    @counts['pending_messages_count'] += 1
    @counts['failed_messages_count'] += 1
  end

  def historical_group?(thread, message)
    thread['id'].to_s.end_with?('@g.us') || thread['recipient_type'] == 'group' || Whatsapp::GroupEventPolicy.group_record?(message)
  end

  def message_params(message, outgoing)
    peer = outgoing ? message[:to] : message[:from]
    message = message.merge((outgoing ? :to_user_id : :from_user_id) => peer) if peer.to_s.match?(/\A[A-Z]{2}\.\d{8,32}\z/)
    value = { metadata: { display_phone_number: @channel.phone_number.delete_prefix('+'),
                          phone_number_id: @channel.provider_config['phone_number_id'] } }
    value[outgoing ? :message_echoes : :messages] = [message]
    { entry: [{ changes: [{ field: outgoing ? 'smb_message_echoes' : 'messages', value: value }] }] }.with_indifferent_access
  end

  def result_counter(result)
    return 'pending_messages_count' unless result
    return 'duplicate_messages_count' unless result.previously_new_record?

    'imported_messages_count'
  end

  def historical_outgoing?(message)
    return false if message[:to].blank?

    business = Whatsapp::InboxLinkPhoneService.normalize(@channel.phone_number)
    unless Whatsapp::InboxLinkPhoneService.normalize(message[:from]) == business
      raise Whatsapp::HistoryContactResolver::Pending, 'Business sender mismatch'
    end

    true
  end

  def business_sender?(sender)
    Whatsapp::InboxLinkPhoneService.normalize(sender) == Whatsapp::InboxLinkPhoneService.normalize(@channel.phone_number)
  end

  def validate_peer!(peer, message, outgoing)
    sender = outgoing ? message[:to] : message[:from]
    raise Whatsapp::HistoryContactResolver::Pending, 'Historical thread participant mismatch' unless same_peer?(sender, peer)
  end

  def same_peer?(sender, peer)
    sender.present? && (sender.to_s == peer.to_s || (Whatsapp::InboxLinkPhoneService.normalize(sender).present? &&
      Whatsapp::InboxLinkPhoneService.normalize(sender) == Whatsapp::InboxLinkPhoneService.normalize(peer)))
  end
end
