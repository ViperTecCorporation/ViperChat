class Whatsapp::Unoapi::ContactSync::ExportJob < MutexApplicationJob
  queue_as :low

  BATCH_SIZE = 50
  NEXT_BATCH_DELAY = 2.seconds
  LOCK_TIMEOUT = 15.minutes

  retry_on_lock_conflict wait: 30.seconds, attempts: 20
  retry_on Whatsapp::Unoapi::ContactSync::Client::TransientError, wait: :polynomially_longer, attempts: 3

  def perform(channel_id, after_contact_id = 0)
    channel = Channel::Whatsapp.find_by(id: channel_id)
    return unless eligible?(channel)

    with_lock("unoapi-contact-export:#{channel.id}", LOCK_TIMEOUT) do
      export_batch(channel, after_contact_id)
    end
  end

  private

  def eligible?(channel)
    channel&.provider == 'unoapi' &&
      channel.contact_sync_enabled? &&
      channel.contact_export_enabled?
  end

  def export_batch(channel, after_contact_id)
    contact_ids = channel.inbox.contact_inboxes
                         .joins(:contact)
                         .where('contacts.id > ?', after_contact_id)
                         .where.not(contacts: { phone_number: [nil, ''] })
                         .distinct
                         .order('contacts.id')
                         .limit(BATCH_SIZE)
                         .pluck('contacts.id')
    return if contact_ids.empty?

    contacts = channel.account.contacts.where(id: contact_ids).index_by(&:id)
    client = Whatsapp::Unoapi::ContactSync::Client.new(channel)
    contact_ids.each do |contact_id|
      export_contact(channel, contacts.fetch(contact_id), client)
    end

    schedule_next_batch(channel, contact_ids.last) if contact_ids.size == BATCH_SIZE
  end

  def export_contact(channel, contact, client)
    Whatsapp::Unoapi::ContactSync::ContactExporter.new(channel: channel, contact: contact, client: client).perform
  rescue Whatsapp::Unoapi::ContactSync::Client::TransientError => e
    Rails.logger.error(
      "[UNOAPI CONTACT EXPORT] channel_id=#{channel.id} contact_id=#{contact.id} " \
      "transient_error=#{e.class}: #{e.message}"
    )
  end

  def schedule_next_batch(channel, after_contact_id)
    self.class.set(wait: NEXT_BATCH_DELAY).perform_later(channel.id, after_contact_id)
  end
end
