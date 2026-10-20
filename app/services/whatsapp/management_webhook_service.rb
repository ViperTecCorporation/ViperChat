require 'digest'

class Whatsapp::ManagementWebhookService
  include Whatsapp::HistoryWebhookFiltering

  def initialize(params:)
    @params = params.to_h.deep_stringify_keys
  end

  def perform
    @received_at = Time.current
    return [] if @params['phone_number'].blank?

    # The authenticated URL is the sole anchor. Never discover another tenant from webhook contents.
    channel = Channel::Whatsapp.find_by(phone_number: @params['phone_number'], provider: 'whatsapp_cloud')
    return [] unless channel

    channel.with_lock do
      next [] unless channel.account.active?

      Array(@params['entry']).flat_map { |entry| receive_entry(channel, entry) }
    end
  end

  private

  def receive_entry(channel, entry)
    return [] unless owned_entry?(channel, entry)

    Array(entry['changes']).flat_map do |change|
      next unless management_change?(change)
      next unless owned_phone_value?(channel, change['value'])

      Whatsapp::HistoryWebhookChunks.split(change).map { |part| receive_change(channel, entry, part) }
    end.compact
  end

  def owned_entry?(channel, entry)
    return false unless entry.is_a?(Hash)

    waba = channel.provider_config['business_account_id']
    waba.present? && entry['id'].to_s == waba.to_s
  end

  def management_change?(change)
    return false unless change.is_a?(Hash) && change['field'].is_a?(String) && change['field'].present?

    (Whatsapp::WebhookFields::MESSAGING + %w[calls]).exclude?(change['field'])
  end

  def owned_phone_value?(channel, value)
    return true unless value.is_a?(Hash)

    sources = [value, value['metadata']].grep(Hash)
    return false unless sources.all? { |source| owned_phone_id?(channel, source) }

    owned_display_phone?(channel, value)
  end

  def owned_phone_id?(channel, source)
    return true unless source.key?('phone_number_id')

    source['phone_number_id'].present? && source['phone_number_id'].to_s == channel.provider_config['phone_number_id'].to_s
  end

  def owned_display_phone?(channel, value)
    return true unless value.key?('display_phone_number')

    digits = value['display_phone_number'].to_s.gsub(/\D/, '')
    digits.present? && digits == channel.phone_number.gsub(/\D/, '')
  end

  def receive_change(channel, entry, change)
    identity = { 'entry_id' => entry['id'], 'time' => entry['time'], 'value' => change['value'] }
    digest = Digest::SHA256.hexdigest(canonical(identity).to_json)
    scope = { account: channel.account, channel: channel, field: change['field'], digest: digest }
    existing = WhatsappManagementEvent.find_by(scope)
    return existing if existing

    event = WhatsappManagementEvent.create_or_find_by!(scope) do |row|
      row.assign_attributes(receipt_attributes(channel, entry, change).merge(
                              inbox: channel.inbox, expires_at: @received_at + WhatsappManagementEvent::RETENTION
                            ))
    end
    created = event.previously_new_record?
    event.with_lock do
      apply_template_invalidation(channel, event) if created && Whatsapp::WebhookFields::TEMPLATE.include?(event.field)
    end
    event
  end

  def apply_template_invalidation(channel, event)
    if channel.reauthorization_required?
      event.update!(state: 'review', reason: 'reauthorization_required')
      return
    end

    # Skip channel callbacks: updating config would trigger unrelated provider operations.
    channel.update_columns(message_templates_last_updated: nil) # rubocop:disable Rails/SkipsModelValidations
    job = Channels::Whatsapp::TemplatesSyncJob.perform_later(channel)
    raise ActiveJob::EnqueueError, 'Template sync could not be enqueued' unless job

    event.update!(state: 'processed')
  end

  def receipt_attributes(channel, entry, change)
    details = snapshot_details(change['value'])
    return history_receipt_attributes(channel, entry, change, details) if change['field'] == 'history'

    payload, truncated = retained_payload(entry, change)
    if change['field'] == 'smb_app_state_sync'
      return { payload: payload, truncated: truncated, details: details,
               state: truncated ? 'review' : 'pending_import', reason: truncated ? 'payload_too_large' : 'user_choice_required' }
    end

    reason = 'unknown_field' unless Whatsapp::WebhookFields::ALL.include?(change['field'])
    { payload: payload, truncated: truncated, details: details, state: 'recorded', reason: reason }
  end

  def history_receipt_attributes(channel, entry, change, details)
    # This is a lifecycle refusal, not a malformed batch or an import request.
    if history_refused?(change['value'])
      return { payload: {}, truncated: false, details: details.merge('status' => 'DISABLED'), state: 'recorded', reason: nil }
    end

    config = channel.provider_config
    unless config.fetch('ignore_history_messages', true) == false
      return { payload: {}, truncated: false, details: history_counts(change['value']).merge(details),
               state: 'recorded', reason: 'history_ignored' }
    end

    # Never retain an unfiltered unknown message-history format.
    filtered, counts = filtered_history(change['value'], config)
    unless filtered
      return { payload: {}, truncated: false, details: details.merge(history_counts(change['value'])),
               state: 'review', reason: 'unsupported_history_format' }
    end

    payload, truncated = retained_payload(entry.slice('id', 'time'), change.slice('field').merge('value' => filtered))
    { payload: payload, truncated: truncated, details: details.merge(counts).merge(Whatsapp::HistoryImportService.scope_snapshot(channel.inbox)),
      state: truncated ? 'review' : 'pending_import', reason: truncated ? 'payload_too_large' : 'automatic_import_pending' }
  end

  def retained_payload(entry, change)
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    payload = filter.filter({ 'entry' => [entry.except('changes').merge('changes' => [change])] })
    bytes = payload.to_json.bytesize
    return [payload, false] if bytes <= WhatsappManagementEvent::MAX_PAYLOAD_BYTES

    # Do not retain a raw/invalid JSON prefix (or split UTF-8); large imports await user consent.
    [{ 'truncated' => true, 'original_bytes' => bytes }, true]
  end

  def snapshot_details(value)
    return {} unless value.is_a?(Hash)

    details = WhatsappManagementEvent.snapshot_details(value)

    %w[contacts messages].each do |key|
      details["#{key}_count"] = value[key].length if value[key].is_a?(Array)
    end
    details['contacts_count'] = value['state_sync'].count { |item| state_sync_contact?(item) } if value['state_sync'].is_a?(Array)
    details
  end

  def state_sync_contact?(item)
    item.is_a?(Hash) && item['type'] == 'contact' && item['contact'].is_a?(Hash)
  end

  def canonical(value)
    case value
    when Hash then value.sort.to_h.transform_values { |item| canonical(item) }
    when Array then value.map { |item| canonical(item) }
    else value
    end
  end
end
