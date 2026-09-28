class Whatsapp::OneoffUnoapiCampaignService
  pattr_initialize [:campaign!]

  def perform
    raise 'WhatsApp campaigns feature not enabled' unless campaign.account.feature_enabled?(:whatsapp_campaign)

    raise "Invalid campaign #{campaign.id}" if inbox.inbox_type != 'Whatsapp' || channel.provider != 'unoapi' || !campaign.one_off?
    raise 'Completed Campaign' if campaign.completed?

    # marks campaign completed so that other jobs won't pick it up
    campaign.completed!

    process_audience(campaign.audience)
  end

  private

  delegate :inbox, to: :campaign
  delegate :channel, to: :inbox

  def process_audience(audience)
    audience ||= []
    label_entries = audience.select { |entry| entry['type'] == 'Label' }
    manual_entries = audience.reject { |entry| entry['type'] == 'Label' }
    expanded_audience = expand_label_audience(audience)
    full_audience = merge_audiences(manual_entries, expanded_audience)
    Rails.logger.debug { "Process campaign #{campaign.id} and #{full_audience.length} audience record(s)" }
    interval = 0
    processed_manual = manual_entries.map do |a|
      update_audience(a.symbolize_keys)
    end
    full_audience.each do |a|
      aa = update_audience(a.symbolize_keys)
      interval = schedule_job(campaign, aa, interval) if aa[:status] == :scheduled
    end
    # rubocop:disable Rails/SkipsModelValidations
    campaign.update_column(:audience, processed_manual + label_entries)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def update_audience(audience)
    audience[:status] = valid_phone_number?(audience[:phone_number]) ? :scheduled : :error
    audience[:audience_id] = audience[:audience_id] || SecureRandom.uuid
    audience.symbolize_keys
  end

  def valid_phone_number?(phone_number)
    phone_number.present? && phone_number.match?(/\A\+[1-9]\d{1,14}\z/)
  end

  def expand_label_audience(audience)
    label_ids = audience.select { |entry| entry['type'] == 'Label' }.map { |entry| entry['id'] }
    return [] if label_ids.blank?

    label_titles = campaign.account.labels.where(id: label_ids).pluck(:title)
    contacts = campaign.account.contacts.tagged_with(label_titles, any: true)
    contacts.map { |contact| contact_to_audience(contact) }
  end

  def merge_audiences(audience, expanded_audience)
    manual = audience.reject { |entry| entry['type'] == 'Label' }
    combined = manual + expanded_audience
    combined.uniq do |entry|
      (entry[:phone_number] || entry['phone_number']).to_s.presence ||
        (entry[:email] || entry['email']).to_s.presence ||
        (entry[:identifier] || entry['identifier']).to_s.presence ||
        (entry[:audience_id] || entry['audience_id']).to_s
    end
  end

  def contact_to_audience(contact)
    {
      name: contact.name,
      phone_number: contact.phone_number,
      identifier: contact.identifier,
      email: contact.email
    }.compact
  end

  def schedule_job(campaign, audience, interval)
    interval = audience[:wait_for_seconds] || (interval + rand(10..180))
    CampaignMessageJob.set(wait: interval.seconds).perform_later(
      campaign.account_id,
      campaign.inbox_id,
      campaign.id,
      campaign.message,
      audience
    )
    interval
  end
end
