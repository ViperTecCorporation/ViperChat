# Retire routing evidence, never remove historical aliases, conversations or messages.
class Whatsapp::ContactPhoneChangeService
  def self.changed?(contact)
    return false unless contact.persisted? && contact.will_save_change_to_phone_number?

    previous = Whatsapp::InboxLinkPhoneService.normalize(contact.phone_number_in_database)
    current = Whatsapp::InboxLinkPhoneService.normalize(contact.phone_number)
    previous.present? && current.present? && previous != current && !legacy_phone_correction?(previous, current)
  end

  def self.legacy_phone_correction?(previous, current)
    shorter, longer = [previous, current].sort_by(&:length)
    shorter.match?(/\A55\d{10}\z/) && longer == "#{shorter[0, 4]}9#{shorter[4..]}" &&
      Phonelib.parse("+#{shorter}").valid? && Phonelib.parse("+#{shorter}").type == :fixed_line
  end

  def self.retired?(contact, inbox, *source_ids)
    inbox.whatsapp? && contact.contact_inboxes.where(inbox: inbox, source_id: source_ids.compact_blank).any?(&:whatsapp_identity_retired?)
  end

  def initialize(contact:)
    @contact = contact
  end

  def perform
    return unless self.class.changed?(@contact)
    return if links.empty? && change.values_at('bsuid', 'username').all?(&:blank?)

    retire_aliases
    create_phone_aliases(links.map(&:inbox).uniq.select { |inbox| inbox.channel.provider == 'unoapi' })
    record_change(change)
  end

  private

  def change
    @change ||= { 'from' => @contact.phone_number_in_database, 'to' => @contact.phone_number,
                  'at' => Time.current.iso8601(6), 'bsuid' => @contact.bsuid_in_database,
                  'username' => @contact.whatsapp_username_in_database }.compact
  end

  def links
    @links ||= @contact.contact_inboxes.joins(:inbox).where(inboxes: { channel_type: 'Channel::Whatsapp' })
                       .includes(inbox: :channel).reject { |link| link.source_id.end_with?('@g.us') }
  end

  def retire_aliases
    links.each do |link|
      next if link.whatsapp_identity_retired? || current_phone_alias?(link)

      link.update!(additional_attributes: link.additional_attributes.merge('whatsapp_identity_retired' => change))
    end
  end

  def current_phone_alias?(link)
    Whatsapp::InboxLinkPhoneService.normalize(link.source_id) == Whatsapp::InboxLinkPhoneService.normalize(@contact.phone_number)
  end

  def create_phone_aliases(inboxes)
    inboxes.each do |inbox|
      source = @contact.phone_number.delete_prefix('+')
      link = inbox.contact_inboxes.create_or_find_by!(source_id: source) { |row| row.contact = @contact }
      if link.contact_id == @contact.id
        link.update!(additional_attributes: link.additional_attributes.except('whatsapp_identity_retired')) if link.whatsapp_identity_retired?
        next
      end

      @contact.errors.add(:phone_number, 'conflicts with an existing WhatsApp identity')
      raise ActiveRecord::RecordInvalid, @contact
    end
  end

  def record_change(change)
    attributes = @contact.additional_attributes || {}
    @contact.additional_attributes = attributes.merge('whatsapp_phone_changes' => Array(attributes['whatsapp_phone_changes']) + [change])
    @contact.bsuid = nil if @contact.bsuid == @contact.bsuid_in_database
    @contact.whatsapp_username = nil if @contact.whatsapp_username == @contact.whatsapp_username_in_database
  end
end
