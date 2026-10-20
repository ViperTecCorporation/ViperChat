# Split batches before dispatch, so each change/message has its own retry budget.
class Whatsapp::WebhookEnvelope
  def self.units(params)
    body = params.to_h.with_indifferent_access
    Array(body[:entry]).flat_map do |entry|
      next [] unless entry.is_a?(Hash)

      Array(entry[:changes]).flat_map do |change|
        next [] unless change.is_a?(Hash)

        values(change).map do |value|
          body.slice(:object, :phone_number, :whatsapp_channel_id, :whatsapp_provider)
              .merge(entry: [entry.except(:changes).merge(changes: [change.merge(value: value)])])
        end
      end
    end
  end

  def self.administrative?(field)
    field.present? && %w[messages smb_message_echoes message_echoes calls].exclude?(field)
  end

  def self.values(change)
    value = change[:value]
    return [value] unless value.is_a?(Hash)

    value = value.with_indifferent_access
    return [value] unless %w[messages smb_message_echoes message_echoes].include?(change[:field])

    parts = message_values(value)
    parts << value.except(:messages, :message_echoes).merge(statuses: value[:statuses]) if value[:statuses].present?
    parts.size > 1 ? parts : [value]
  end

  def self.message_values(value)
    %i[messages message_echoes].flat_map do |key|
      Array(value[key]).filter_map { |message| message_value(value, key, message) if message.is_a?(Hash) }
    end
  end

  def self.message_value(value, key, message)
    item = value.except(:messages, :message_echoes, :statuses).merge(key => [message])
    item[:contacts] = matching_contacts(value, message) if key == :messages && Array(value[:messages]).size > 1
    item
  end

  def self.matching_contacts(value, message)
    peers = message.values_at(:from, :from_user_id, :from_parent_user_id).compact
    Array(value[:contacts]).select do |contact|
      contact.is_a?(Hash) && contact.values_at(:wa_id, :user_id, :parent_user_id).intersect?(peers)
    end
  end
  private_class_method :values, :message_values, :message_value, :matching_contacts
end
