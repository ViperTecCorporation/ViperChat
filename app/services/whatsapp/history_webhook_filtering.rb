# Retain only known history envelopes and messages inside the configured period.
module Whatsapp::HistoryWebhookFiltering
  private

  def history_counts(value)
    return {} unless value.is_a?(Hash)

    histories = value['history']
    return { 'messages_count' => value['messages'].length } if value['messages'].is_a?(Array) && !histories.is_a?(Array)
    return {} unless histories.is_a?(Array)

    threads = history_array_children(histories, 'threads')
    messages = history_array_children(threads, 'messages') + Array(value['messages'])
    { 'history_count' => histories.length, 'threads_count' => threads.length, 'messages_count' => messages.length }
  end

  def history_array_children(items, key)
    items.grep(Hash).filter_map { |item| item[key] if item[key].is_a?(Array) }.flatten(1)
  end

  def filtered_history(value, config)
    return unless valid_history_value?(value)

    cutoff = @received_at - config.fetch('history_max_age_days', 7).to_i.clamp(1, 3650).days
    counts = history_counts(value).merge('kept_messages_count' => 0, 'dropped_messages_count' => 0, 'invalid_messages_count' => 0)
    filtered = history_envelope(value)
    filtered['history'] = value['history'].map { |history| filtered_history_chunk(history, cutoff, counts) } if value.key?('history')
    filtered['messages'] = value['messages'].select { |message| keep_history_message?(message, cutoff, counts) } if value.key?('messages')
    [filtered, counts]
  end

  def valid_history_value?(value)
    return false unless value.is_a?(Hash)
    return false unless value.key?('history') || value.key?('messages')
    return false if value.key?('messages') && !history_message_array?(value['messages'])

    !value.key?('history') || valid_history_chunks?(value['history'])
  end

  def history_message_array?(messages)
    messages.is_a?(Array) && messages.all?(Hash)
  end

  def valid_history_chunks?(histories)
    histories.is_a?(Array) && histories.all? { |history| valid_history_chunk?(history) }
  end

  def history_refused?(value)
    return false unless value.is_a?(Hash) && value['history'].is_a?(Array)

    history_array_children(value['history'], 'errors').grep(Hash).any? { |error| error['code'].to_s == '2593109' }
  end

  def valid_history_chunk?(history)
    history.is_a?(Hash) && history['threads'].is_a?(Array) && history['threads'].all? { |thread| valid_history_thread?(thread) }
  end

  def valid_history_thread?(thread)
    thread.is_a?(Hash) && history_message_array?(thread['messages'])
  end

  def history_envelope(value)
    result = value.slice('messaging_product', 'progress', 'phase', 'errors')
    result['metadata'] = value['metadata'].slice('phone_number_id', 'display_phone_number') if value['metadata'].is_a?(Hash)
    result
  end

  def filtered_history_chunk(history, cutoff, counts)
    result = history.slice('progress', 'phase', 'chunk_order', 'errors')
    result['metadata'] = history['metadata'].slice('progress', 'phase', 'chunk_order') if history['metadata'].is_a?(Hash)
    result['threads'] = history['threads'].map do |thread|
      messages = thread['messages'].select { |message| keep_history_message?(message, cutoff, counts) }
      thread.slice('id').merge('messages' => messages)
    end
    result
  end

  def keep_history_message?(message, cutoff, counts)
    timestamp = history_timestamp(message['timestamp'])
    keep = timestamp && timestamp >= cutoff && timestamp <= @received_at
    counts['invalid_messages_count'] += 1 unless timestamp
    counts[keep ? 'kept_messages_count' : 'dropped_messages_count'] += 1
    keep
  end

  def history_timestamp(value)
    return unless value.to_s.match?(/\A\d{1,12}\z/)

    Time.zone.at(value.to_s.to_i)
  end
end
