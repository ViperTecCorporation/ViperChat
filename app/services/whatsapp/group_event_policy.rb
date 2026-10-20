# Applied before identity observation, contact creation and attachment downloads.
class Whatsapp::GroupEventPolicy
  COLLECTIONS = %i[messages message_echoes statuses contacts].freeze

  def self.group_record?(record)
    return false unless record.is_a?(Hash)

    record = record.with_indifferent_access
    record[:group_id].present? || record[:recipient_type] == 'group' ||
      %i[from to recipient_id wa_id].any? { |key| record[key].to_s.end_with?('@g.us') }
  end

  def initialize(inbox:)
    @inbox = inbox
  end

  def enabled?
    @inbox.channel.provider == 'whatsapp_cloud' && @inbox.channel.provider_config['ignore_group_messages'] == true
  end

  def ignored?(value, field: nil)
    return false unless enabled?
    return true if field.to_s.start_with?('group_') || self.class.group_record?(value)
    return false unless value.is_a?(Hash)

    records = event_records(value)
    return true if inherited_group?(value, records)

    group_records?(records)
  end

  def filter(value)
    return value unless enabled? && value.is_a?(Hash)

    result = value.deep_dup
    COLLECTIONS.each do |key|
      next unless result[key].is_a?(Array)

      result[key] = result[key].reject { |record| self.class.group_record?(record) }
    end
    result
  end

  private

  def event_records(value)
    records = %i[messages message_echoes statuses].flat_map { |key| Array(value[key]) }
    records.empty? ? Array(value[:contacts]) : records
  end

  def inherited_group?(value, records)
    contacts = Array(value[:contacts])
    group_records?(contacts) && Array(value[:statuses]).empty? &&
      records.all? { |record| record.is_a?(Hash) && record[:group_id].blank? }
  end

  def group_records?(records)
    records.present? && records.all? { |record| self.class.group_record?(record) }
  end
end
