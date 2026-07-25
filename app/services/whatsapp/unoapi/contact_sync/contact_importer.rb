class Whatsapp::Unoapi::ContactSync::ContactImporter
  class InvalidContactError < StandardError; end
  class IdentityConflictError < StandardError; end

  def initialize(channel:, payload:)
    @channel = channel
    @inbox = channel.inbox
    @account = channel.account
    @payload = payload.with_indifferent_access
  end

  def perform
    validate_identity!
    return :skipped if already_imported?

    contact = nil
    @account.with_lock { contact = import_contact }
    enqueue_avatar(contact)
    :processed
  rescue ActiveRecord::RecordNotUnique
    @account.with_lock { contact = import_contact }
    enqueue_avatar(contact)
    :processed
  end

  private

  def import_contact
    contacts = candidate_contacts
    contact = merge_compatible_contacts(contacts)
    contact ||= create_contact
    update_contact(contact)
    update_contact_inboxes(contact)
    contact
  end

  def candidate_contacts
    contacts = @inbox.contact_inboxes.where(source_id: source_ids).includes(:contact).map(&:contact)
    contacts << @account.contacts.find_by(phone_number: phone_number) if phone_number.present?
    contacts << @account.contacts.find_by(bsuid: user_id) if user_id.present?
    contacts.compact.uniq
  end

  def merge_compatible_contacts(contacts)
    return contacts.first if contacts.one?
    return if contacts.empty?

    base = contacts.find { |contact| contact.phone_number == phone_number } || contacts.first
    (contacts - [base]).each do |mergee|
      ensure_mergeable!(base, mergee)
      ContactMergeAction.new(account: @account, base_contact: base, mergee_contact: mergee).perform
      base.reload
    end
    base
  end

  def ensure_mergeable!(left, right)
    if left.bsuid.present? && right.bsuid.present? && left.bsuid != right.bsuid
      raise IdentityConflictError, "LID conflict: #{left.bsuid} != #{right.bsuid}"
    end
    return if left.phone_number.blank? || right.phone_number.blank? || left.phone_number == right.phone_number

    raise IdentityConflictError, "phone conflict: #{left.phone_number} != #{right.phone_number}"
  end

  def create_contact
    @account.contacts.create!(
      name: preferred_name || phone_number || user_id,
      phone_number: phone_number,
      bsuid: user_id,
      whatsapp_username: username
    )
  end

  def update_contact(contact)
    ensure_payload_matches_contact!(contact)
    attributes = {
      phone_number: contact.phone_number.presence || phone_number,
      bsuid: contact.bsuid.presence || user_id,
      whatsapp_username: username.presence || contact.whatsapp_username
    }.compact
    attributes[:name] = preferred_name if invalid_name?(contact.name) && preferred_name.present?
    contact.update!(attributes)
  end

  def ensure_payload_matches_contact!(contact)
    if contact.bsuid.present? && user_id.present? && contact.bsuid != user_id
      raise IdentityConflictError, "contact #{contact.id} already belongs to LID #{contact.bsuid}"
    end
    return if contact.phone_number.blank? || phone_number.blank? || contact.phone_number == phone_number

    raise IdentityConflictError, "contact #{contact.id} already belongs to phone #{contact.phone_number}"
  end

  def update_contact_inboxes(contact)
    source_ids.each do |source_id|
      contact_inbox = @inbox.contact_inboxes.find_or_create_by!(source_id: source_id) do |record|
        record.contact = contact
      end
      raise IdentityConflictError, "source #{source_id} belongs to contact #{contact_inbox.contact_id}" if contact_inbox.contact_id != contact.id

      attributes = (contact_inbox.additional_attributes || {}).merge('unoapi_last_updated_ms' => last_updated_ms)
      contact_inbox.update!(additional_attributes: attributes)
    end
  end

  def already_imported?
    return false if last_updated_ms.zero?

    links = @inbox.contact_inboxes.where(source_id: source_ids).to_a
    return false unless links.size == source_ids.size
    return false unless links.map(&:contact_id).uniq.one?
    return false if duplicate_account_phone?(links.first.contact_id)

    links.all? { |link| link.additional_attributes['unoapi_last_updated_ms'].to_i >= last_updated_ms }
  end

  def duplicate_account_phone?(contact_id)
    return false if phone_number.blank?

    @account.contacts.where(phone_number: phone_number).where.not(id: contact_id).exists?
  end

  def validate_identity!
    raise InvalidContactError, 'contact has neither user_id nor phone_number' if source_ids.empty?
  end

  def source_ids
    @source_ids ||= [user_id, normalized_phone].compact_blank.uniq
  end

  def user_id
    @user_id ||= @payload[:user_id].to_s.strip.presence
  end

  def username
    @payload[:username].to_s.strip.presence
  end

  def last_updated_ms
    @payload[:last_updated_ms].to_i
  end

  def phone_number
    "+#{normalized_phone}" if normalized_phone.present?
  end

  def normalized_phone
    return @normalized_phone if defined?(@normalized_phone)

    @normalized_phone = normalize_phone(raw_phone_digits)
  end

  def raw_phone_digits
    @raw_phone_digits ||= @payload[:phone_number].to_s.gsub(/\D/, '')
  end

  def normalize_phone(digits)
    return if digits.blank?

    if digits.start_with?('55')
      return "#{digits[0, 4]}9#{digits[4..]}" if digits.length == 12
      return digits if digits.length == 13 && digits[4] == '9'

      raise InvalidContactError, "invalid Brazilian mobile phone: #{digits}"
    end
    return digits if digits.match?(/\A[1-9]\d{1,14}\z/)

    raise InvalidContactError, "invalid E.164 phone: #{digits}"
  end

  def preferred_name
    @preferred_name ||= [@payload[:display_name], @payload[:push_name]]
                        .map { |name| name.to_s.strip }
                        .find { |name| valid_name?(name) }
  end

  def invalid_name?(name)
    !valid_name?(name)
  end

  def valid_name?(name)
    value = name.to_s.strip
    return false if value.each_grapheme_cluster.count < 3
    return false unless value.match?(/[\p{L}\p{N}]/)

    digits = value.gsub(/\D/, '')
    digits.blank? || [raw_phone_digits, normalized_phone].compact_blank.exclude?(digits)
  end

  def enqueue_avatar(contact)
    picture = @payload[:picture].to_s.strip
    Avatar::AvatarFromUrlJob.enqueue_if_needed(contact, picture) if picture.present?
  end
end
