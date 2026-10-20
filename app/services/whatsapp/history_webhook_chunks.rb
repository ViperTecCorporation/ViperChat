# Large history batches must not be truncated before their messages can import.
module Whatsapp::HistoryWebhookChunks
  def self.split(change)
    return [change] unless oversize_history?(change)

    value = change['value']
    return [change] unless value.is_a?(Hash)

    media_parts = media_changes(change, value)
    return media_parts.presence || [change] unless value.key?('history')

    histories = value['history']
    return [change] unless valid_histories?(histories)

    parts = history_changes(change, histories) + media_parts
    parts.empty? ? [change] : parts
  end

  def self.oversize_history?(change)
    change['field'] == 'history' && change.to_json.bytesize > WhatsappManagementEvent::MAX_PAYLOAD_BYTES
  end

  def self.media_changes(change, value)
    return [] unless value['messages'].is_a?(Array) && value['messages'].all?(Hash)

    value['messages'].map { |message| change.merge('value' => value.except('history').merge('messages' => [message])) }
  end

  def self.history_changes(change, histories)
    histories.flat_map do |history|
      history['threads'].flat_map do |thread|
        thread['messages'].map { |message| singleton_change(change, history, thread, message) }
      end
    end
  end

  def self.valid_histories?(histories)
    histories.is_a?(Array) && histories.all? do |item|
      item.is_a?(Hash) && item['threads'].is_a?(Array) && item['threads'].all? do |thread|
        thread.is_a?(Hash) && thread['messages'].is_a?(Array)
      end
    end
  end

  def self.singleton_change(change, history, thread, message)
    item = thread.except('messages').merge('messages' => [message])
    chunk = history.except('threads').merge('threads' => [item])
    value = change['value'].except('history', 'messages').merge('history' => [chunk])
    change.merge('value' => value)
  end
  private_class_method :valid_histories?, :singleton_change, :media_changes, :history_changes, :oversize_history?
end
