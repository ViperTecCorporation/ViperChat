class Whatsapp::PartnerInboxReportCountersService
  def self.count(rows)
    Whatsapp::PartnerInboxReportService::PROVIDERS.index_with do |provider|
      matching = rows.select { |row| row[:provider] == provider }
      { incoming: rows.count { |row| received_on?(row, provider) },
        outgoing: matching.count { |row| row[:direction] == 'outgoing' },
        delivered: matching.count { |row| row[:direction] == 'outgoing' && row[:delivered] } }
    end.merge(metadata(rows))
  end

  def self.metadata(rows)
    referrals = rows.select { |row| row[:ad_referral] }
    { 'unique_messages' => rows.size, 'ad_referrals' => referrals.size, 'ad_contacts' => referrals.pluck(:contact_id).uniq.size }
  end
  private_class_method :metadata

  def self.daily(rows, zone:, since:, until_time:)
    by_date = rows.group_by { |row| row[:created_at].in_time_zone(zone).to_date }
    (since.to_date...until_time.to_date).map do |date|
      { date: date.iso8601, counts: count(by_date.fetch(date, [])) }
    end
  end

  def self.received_on?(row, provider)
    row[:direction] == 'incoming' && (row[:received_providers].include?(provider) || (provider == 'unknown' && row[:received_providers].empty?))
  end
  private_class_method :received_on?
end
