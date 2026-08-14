class Whatsapp::Unoapi::ContactSync::ContactImporter # rubocop:disable Metrics/ClassLength
  class InvalidContactError < StandardError; end
  class IdentityConflictError < StandardError; end

  WHATSAPP_JID_SUFFIXES = %w[@lid @s.whatsapp.net @g.us @broadcast @newsletter].freeze

  def self.build_for_page(channel:, payloads:, client: nil) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    importers = payloads.map { |payload| new(channel: channel, payload: payload, client: client) }
    identities = importers.filter_map do |importer|
      importer.identity_for_preload
    rescue InvalidContactError
      nil
    end

    source_ids = identities.flat_map { |identity| identity[:source_ids] }.uniq
    phone_numbers = identities.filter_map { |identity| identity[:phone_number] }.uniq
    links_by_source_id = channel.inbox.contact_inboxes.where(source_id: source_ids).includes(:contact).to_a.group_by(&:source_id)
    contact_ids_by_phone = channel.account.contacts.where(phone_number: phone_numbers)
                                  .pluck(:phone_number, :id)
                                  .group_by(&:first)
                                  .transform_values { |pairs| pairs.map(&:last) }

    importers.each do |importer|
      importer.preload_idempotency!(
        links_by_source_id: links_by_source_id,
        contact_ids_by_phone: contact_ids_by_phone
      )
    end
    importers
  end

  def initialize(channel:, payload:, client: nil)
    @channel = channel
    @inbox = channel.inbox
    @account = channel.account
    @payload = payload.with_indifferent_access
    @client = client
  end

  def identity_for_preload
    { source_ids: source_ids, phone_number: phone_number }
  end

  def preload_idempotency!(links_by_source_id:, contact_ids_by_phone:)
    @links_by_source_id = links_by_source_id
    @contact_ids_by_phone = contact_ids_by_phone
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
    sanitize_legacy_emails!(contacts)
    verify_conflicting_lid!(contacts) if conflicting_lid?(contacts)
    contacts = candidate_contacts if @network_identity_verified
    sanitize_legacy_emails!(contacts)
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

  def sanitize_legacy_emails!(contacts)
    contacts.each do |contact|
      next unless repairable_email?(contact)

      contact.update_columns(email: nil, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def ensure_mergeable!(left, right) # rubocop:disable Metrics/CyclomaticComplexity
    if left.bsuid.present? && right.bsuid.present? && left.bsuid != right.bsuid && !verified_contacts?(left, right)
      raise IdentityConflictError, "LID conflict: #{left.bsuid} != #{right.bsuid}"
    end
    return if left.phone_number.blank? || right.phone_number.blank? || equivalent_phone_numbers?(left.phone_number, right.phone_number)

    raise IdentityConflictError, "phone conflict: #{left.phone_number} != #{right.phone_number}"
  end

  def create_contact
    @account.contacts.create!(
      name: replacement_name || user_id,
      phone_number: phone_number,
      bsuid: user_id,
      whatsapp_username: username
    )
  end

  def update_contact(contact)
    ensure_payload_matches_contact!(contact)
    prepare_legacy_phone_repair(contact)
    attributes = {
      phone_number: @legacy_phone_source_id.present? ? phone_number : contact.phone_number.presence || phone_number,
      bsuid: resolved_bsuid(contact),
      whatsapp_username: username.presence || contact.whatsapp_username
    }.compact
    attributes[:name] = replacement_name if repairable_name?(contact)
    attributes[:email] = nil if repairable_email?(contact)
    contact.update!(attributes)
  end

  def ensure_payload_matches_contact!(contact) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    if contact.bsuid.present? && user_id.present? && contact.bsuid != user_id && !@network_identity_verified
      raise IdentityConflictError, "contact #{contact.id} already belongs to LID #{contact.bsuid}"
    end
    return if contact.phone_number.blank? || phone_number.blank? || contact.phone_number == phone_number
    return if legacy_phone_repair?(contact)

    raise IdentityConflictError, "contact #{contact.id} already belongs to phone #{contact.phone_number}"
  end

  def update_contact_inboxes(contact)
    repair_legacy_phone_source(contact)
    source_ids.each do |source_id|
      contact_inbox = @inbox.contact_inboxes.find_or_create_by!(source_id: source_id) do |record|
        record.contact = contact
      end
      raise IdentityConflictError, "source #{source_id} belongs to contact #{contact_inbox.contact_id}" if contact_inbox.contact_id != contact.id

      attributes = (contact_inbox.additional_attributes || {}).merge('unoapi_last_updated_ms' => last_updated_ms)
      contact_inbox.update!(additional_attributes: attributes)
    end
  end

  def prepare_legacy_phone_repair(contact)
    return unless legacy_phone_repair?(contact)

    @legacy_phone_source_id = contact.phone_number.delete_prefix('+')
    canonical_alias = known_canonical_mobile_alias(contact)
    return if canonical_alias.blank?

    @normalized_phone = canonical_alias
    @source_ids = nil
  end

  def legacy_phone_repair?(contact)
    candidate = legacy_brazilian_mobile_candidate(raw_phone_digits)
    contact_digits = contact.phone_number.to_s.gsub(/\D/, '')
    removes_invalid_ninth_digit = candidate.present? && contact_digits == candidate && valid_phone?(raw_phone_digits)
    inserts_missing_ninth_digit = canonical_brazilian_mobile?(normalized_phone) &&
                                  contact_digits == phone_without_ninth_digit(normalized_phone)

    removes_invalid_ninth_digit || inserts_missing_ninth_digit || known_canonical_mobile_alias(contact).present?
  end

  def known_canonical_mobile_alias(contact)
    contact_digits = contact.phone_number.to_s.gsub(/\D/, '')
    candidate = legacy_brazilian_mobile_candidate(contact_digits)
    return unless canonical_brazilian_mobile?(candidate)

    candidate if @inbox.contact_inboxes.exists?(contact: contact, source_id: candidate)
  end

  def equivalent_phone_numbers?(left, right)
    left_digits = left.to_s.gsub(/\D/, '')
    right_digits = right.to_s.gsub(/\D/, '')
    return true if left_digits == right_digits

    shorter, longer = [left_digits, right_digits].sort_by(&:length)
    shorter.start_with?('55') &&
      legacy_brazilian_mobile_candidate(shorter) == longer &&
      valid_phone?(shorter)
  end

  def conflicting_lid?(contacts)
    return false if user_id.blank?

    contacts.any? { |contact| contact.bsuid.present? && contact.bsuid != user_id }
  end

  def verify_conflicting_lid!(contacts)
    conflicting_contact = contacts.find { |contact| contact.bsuid.present? && contact.bsuid != user_id }
    unless @client && raw_phone_digits.present?
      raise IdentityConflictError, "contact #{conflicting_contact.id} already belongs to LID #{conflicting_contact.bsuid}"
    end

    verification = @client.verify_contact(raw_phone_digits).with_indifferent_access
    verified_lid = verification[:user_id].to_s.strip
    unless verification[:status] == 'valid' && verified_lid.match?(/\A\d+@lid\z/)
      raise IdentityConflictError, "network could not validate LID for contact #{conflicting_contact.id}"
    end

    @user_id = verified_lid
    @source_ids = nil
    @network_identity_verified = true
  end

  def verified_contacts?(*contacts)
    return false unless @network_identity_verified

    contacts.all? do |contact|
      contact.phone_number.blank? || equivalent_phone_numbers?(contact.phone_number, phone_number)
    end
  end

  def resolved_bsuid(contact)
    return user_id if contact.bsuid.blank? || @network_identity_verified

    contact.bsuid
  end

  def repair_legacy_phone_source(contact)
    return if @legacy_phone_source_id.blank?

    contact_inbox = @inbox.contact_inboxes.find_by(contact: contact, source_id: @legacy_phone_source_id)
    return if contact_inbox.blank?

    target = @inbox.contact_inboxes.find_by(source_id: normalized_phone)
    if target&.contact_id == contact.id
      merge_source_links!(contact_inbox, target)
      merge_inbox_conversation_aliases!(contact) if @inbox.lock_to_single_conversation?
      return
    end
    raise IdentityConflictError, "source #{normalized_phone} belongs to contact #{target.contact_id}" if target

    contact_inbox.update!(source_id: normalized_phone)
  end

  def merge_source_links!(source, target)
    Conversation.where(contact_inbox_id: source.id).update_all(contact_inbox_id: target.id) # rubocop:disable Rails/SkipsModelValidations
    target.update!(
      additional_attributes: source.additional_attributes.deep_merge(target.additional_attributes)
    )
    source.delete
  end

  def merge_inbox_conversation_aliases!(contact)
    conversations = @inbox.conversations.non_group_conversations.where(contact_id: contact.id).to_a
    return if conversations.size <= 1

    target = conversations.max_by { |conversation| [conversation.last_activity_at, conversation.id] }
    mergees = conversations - [target]
    Message.where(conversation_id: mergees.map(&:id)).update_all(conversation_id: target.id) # rubocop:disable Rails/SkipsModelValidations
    target.update_columns( # rubocop:disable Rails/SkipsModelValidations
      last_activity_at: conversations.filter_map(&:last_activity_at).max,
      updated_at: Time.current
    )
    mergees.each(&:destroy!)
  end

  def already_imported? # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return false if last_updated_ms.zero?

    links = if @links_by_source_id
              source_ids.flat_map { |source_id| @links_by_source_id.fetch(source_id, []) }
            else
              @inbox.contact_inboxes.where(source_id: source_ids).to_a
            end
    return false unless links.size == source_ids.size
    return false unless links.map(&:contact_id).uniq.one?
    return false if duplicate_account_phone?(links.first.contact_id)
    return false if repairable_name?(links.first.contact)
    return false if repairable_email?(links.first.contact)
    return false if legacy_phone_repair?(links.first.contact)

    imported_at_or_after?(links)
  end

  def repairable_name?(contact)
    invalid_name?(contact.name) && replacement_name.present? && contact.name.to_s.strip != replacement_name
  end

  def repairable_email?(contact)
    value = contact.email.to_s.strip
    return false if value.blank?
    return true unless value.match?(Devise.email_regexp)
    return true if WHATSAPP_JID_SUFFIXES.any? { |suffix| value.downcase.end_with?(suffix) }

    technical_identities = [user_id, raw_phone_digits, normalized_phone, phone_number].compact_blank
    technical_identities.any? { |identity| value.casecmp?(identity.to_s) }
  end

  def imported_at_or_after?(links) = links.all? { |link| link.additional_attributes['unoapi_last_updated_ms'].to_i >= last_updated_ms }

  def duplicate_account_phone?(contact_id)
    return false if phone_number.blank?

    return @contact_ids_by_phone.fetch(phone_number, []).any? { |candidate_id| candidate_id != contact_id } if @contact_ids_by_phone

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
    raise InvalidContactError, "invalid E.164 phone: #{digits}" unless digits.match?(/\A[1-9]\d{1,14}\z/)
    return digits unless digits.start_with?('55')
    return digits if valid_phone?(digits)

    candidate = legacy_brazilian_mobile_candidate(digits)
    return candidate if valid_mobile_phone?(candidate)

    raise InvalidContactError, "invalid Brazilian phone: #{digits}"
  end

  def valid_phone?(digits) = Phonelib.parse("+#{digits}").valid?

  def legacy_brazilian_mobile_candidate(digits)
    "#{digits[0, 4]}9#{digits[4..]}" if digits.length == 12
  end

  def canonical_brazilian_mobile?(digits)
    digits.to_s.match?(/\A55\d{2}9\d{8}\z/) && valid_mobile_phone?(digits)
  end

  def phone_without_ninth_digit(digits)
    digits[0, 4] + digits[5..]
  end

  def valid_mobile_phone?(digits)
    return false if digits.blank?

    phone = Phonelib.parse("+#{digits}")
    phone.valid? && phone.type == :mobile
  end

  def preferred_name
    @preferred_name ||= [@payload[:display_name], @payload[:push_name]]
                        .map { |name| name.to_s.strip }
                        .find { |name| valid_name?(name) }
  end

  def replacement_name = preferred_name || phone_number

  def invalid_name?(name)
    !valid_name?(name)
  end

  def valid_name?(name)
    value = name.to_s.strip
    return false if value.each_grapheme_cluster.count < 3
    return false unless value.match?(/[\p{L}\p{N}]/)
    return false if value.casecmp?(user_id.to_s)
    return false if WHATSAPP_JID_SUFFIXES.any? { |suffix| value.downcase.end_with?(suffix) }

    digits = value.gsub(/\D/, '')
    technical_phone_digits = [raw_phone_digits, normalized_phone, legacy_brazilian_mobile_candidate(raw_phone_digits)].compact_blank
    digits.blank? || technical_phone_digits.exclude?(digits)
  end

  def enqueue_avatar(contact)
    picture = contact_picture_url
    picture_id = contact_picture_id
    metadata = contact_picture_metadata

    if picture_id.present?
      Avatar::AvatarFromUnoapiJob.enqueue_if_needed(contact, @channel, picture_id, metadata, picture.presence)
    elsif picture.present?
      Avatar::AvatarFromUrlJob.enqueue_if_needed(contact, picture, metadata)
    end
  end

  def contact_picture_url
    (@payload[:picture].presence || @payload.dig(:profile, :picture).presence).to_s.strip
  end

  def contact_picture_id
    @payload[:picture_id].presence || @payload[:profile_picture_id].presence || @payload.dig(:profile, :picture_id).presence
  end

  def contact_picture_metadata
    @payload[:picture_metadata].presence || @payload[:profile_picture_metadata].presence || @payload.dig(:profile, :picture_metadata)
  end
end
