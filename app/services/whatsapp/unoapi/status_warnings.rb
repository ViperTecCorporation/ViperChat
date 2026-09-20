# UnoAPI-only status reconciliation; the official Meta channel is unchanged.
module Whatsapp::Unoapi::StatusWarnings
  private

  def process_statuses
    missing_warning_message = false
    Array(processed_params[:statuses]).each do |status|
      unless find_message_by_source_id(status[:id])
        missing_warning_message ||= status[:warnings].present?
        next
      end

      update_whatsapp_identifiers_from_status(status) unless status[:recipient_type].to_s == 'group'
      update_message_with_status(@message, status)
    end
    # The send response may not have stored source_id yet. Reuse the webhook
    # job's RecordNotFound retry; never resend the actual WhatsApp message.
    raise ActiveRecord::RecordNotFound, 'UnoAPI warning awaiting message association' if missing_warning_message
  end

  def update_message_with_status(message, status)
    message.with_lock do
      merge_unoapi_warnings(message, status)
      super
      # A lower status is ignored by the base service, but its warning is not.
      message.save! if message.changed?
    end
  end

  def merge_unoapi_warnings(message, status)
    warnings = Array(status[:warnings]).filter_map do |warning|
      next unless warning.is_a?(Hash) && warning[:code].present?

      { 'code' => warning[:code].to_s, 'message' => warning[:message].to_s }
    end
    return if warnings.empty?

    previous = Array(message.content_attributes['unoapi_warnings'])
    merged = (previous + warnings).uniq { |warning| warning['code'] }
    message.content_attributes = message.content_attributes.merge('unoapi_warnings' => merged)
  end
end
