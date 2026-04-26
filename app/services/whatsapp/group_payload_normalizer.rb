class Whatsapp::GroupPayloadNormalizer
  pattr_initialize [:processed_params!, :inbox!]

  def perform
    return { group: false } if group_source_id.blank?

    {
      group: true,
      group_source_id: group_source_id,
      group_title: contact[:group_subject].presence || group_source_id,
      group_picture: contact[:group_picture],
      sender_identifier: sender_identifier,
      sender_name: contact.dig(:profile, :name),
      sender_picture: contact.dig(:profile, :picture),
      message_source_id: message[:id],
      message_from: message[:from]
    }
  end

  private

  def message
    @message ||= processed_params[:messages]&.first || {}
  end

  def contact
    @contact ||= processed_params[:contacts]&.first || {}
  end

  def group_source_id
    @group_source_id ||= normalize_group_id(message[:group_id].presence || contact[:group_id])
  end

  def sender_identifier
    message[:from].presence || contact[:wa_id]
  end

  def normalize_group_id(value)
    raw = value.to_s.strip
    return '' if raw.blank?
    return raw if raw.end_with?('@g.us')

    digits = raw.gsub(/\D/, '')
    digits.present? ? "#{digits}@g.us" : raw
  end
end
