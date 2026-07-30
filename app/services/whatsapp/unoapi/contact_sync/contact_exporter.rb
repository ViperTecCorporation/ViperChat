require 'digest'

class Whatsapp::Unoapi::ContactSync::ContactExporter
  EXPORT_ATTRIBUTE = 'unoapi_contact_export'.freeze

  def initialize(channel:, contact:, client:)
    @channel = channel
    @contact = contact
    @client = client
  end

  def perform
    return :skipped if links.empty? || imported_from_unoapi?

    payload = export_payload
    return :skipped if payload.blank? || already_attempted?(payload)

    payload = verified_payload(payload)
    return :skipped if already_attempted?(payload)

    response = @client.import_contact(payload)
    remote_contact = response.fetch('contact')
    mark_attempt(payload, status: 'exported', remote_contact: remote_contact)
    :processed
  rescue Whatsapp::Unoapi::ContactSync::Client::PermanentError, ActiveRecord::RecordInvalid,
         ActiveRecord::RecordNotUnique, KeyError => e
    mark_attempt(payload, status: 'failed', error: e.message) if payload.present?
    Rails.logger.error(
      "[UNOAPI CONTACT EXPORT] channel_id=#{@channel.id} contact_id=#{@contact.id} " \
      "error=#{e.class}: #{e.message}"
    )
    :failed
  end

  private

  def links
    @links ||= @channel.inbox.contact_inboxes.where(contact: @contact).to_a
  end

  def imported_from_unoapi?
    links.any? { |link| link.additional_attributes.key?('unoapi_last_updated_ms') }
  end

  def already_attempted?(payload)
    signature = export_signature(payload)
    links.any? { |link| link.additional_attributes.dig(EXPORT_ATTRIBUTE, 'signature') == signature }
  end

  def export_payload
    phone_number = @contact.phone_number.to_s.gsub(/\D/, '')
    return unless phone_number.match?(/\A[1-9]\d{6,14}\z/)

    user_id = lid
    full_name = export_name(phone_number, user_id).first(256)
    {
      phone_number: phone_number,
      full_name: full_name,
      first_name: full_name.split.first.first(128),
      user_id: user_id,
      username: @contact.whatsapp_username.to_s.strip.delete_prefix('@').first(64).presence
    }.compact
  end

  def verified_payload(payload)
    verification = @client.verify_contact(payload[:phone_number]).with_indifferent_access
    verified_lid = verification[:user_id].to_s.strip
    unless verification[:status] == 'valid' && verified_lid.match?(/\A\d+@lid\z/)
      raise Whatsapp::Unoapi::ContactSync::Client::PermanentError, 'UnoAPI could not validate the contact LID'
    end

    network_phone = verified_phone(verification, payload[:phone_number])
    chatwoot_phone = chatwoot_phone(verified_lid, network_phone, payload[:phone_number])
    persist_verified_identity!(verified_lid, network_phone, chatwoot_phone, payload[:phone_number])
    payload.merge(phone_number: chatwoot_phone, user_id: verified_lid)
  end

  def verified_phone(verification, fallback)
    phone_number = verification[:wa_id].to_s.gsub(/\D/, '')
    phone_number.match?(/\A[1-9]\d{6,14}\z/) ? phone_number : fallback
  end

  def chatwoot_phone(verified_lid, network_phone, original_phone)
    candidates = [original_phone, network_phone]
    candidates.concat(@channel.account.contacts.where(bsuid: verified_lid).pluck(:phone_number))
    candidates.concat(
      Contact.joins(contact_inboxes: :inbox)
             .where(account_id: @channel.account.id, inboxes: { account_id: @channel.account.id }, contact_inboxes: { source_id: verified_lid })
             .pluck(:phone_number)
    )
    candidates.map { |phone| phone.to_s.gsub(/\D/, '') }.find { |phone| brazilian_mobile_phone?(phone) } || network_phone
  end

  def brazilian_mobile_phone?(phone_number)
    phone_number.match?(/\A55\d{2}9\d{8}\z/)
  end

  def persist_verified_identity!(verified_lid, network_phone, chatwoot_phone, original_phone)
    Contact.transaction do
      reconcile_identity_contacts!(verified_lid, network_phone, chatwoot_phone)

      attributes = { bsuid: verified_lid, phone_number: "+#{chatwoot_phone}" }
      attributes[:email] = nil if technical_email?(@contact)
      @contact.update_columns(attributes.merge(updated_at: Time.current)) # rubocop:disable Rails/SkipsModelValidations

      replace_source_links!(original_phone, chatwoot_phone)
      replace_source_links!(network_phone, chatwoot_phone)
      normalize_mobile_source_links!(chatwoot_phone)
      stale_lid_links(verified_lid).each { |link| replace_source_link!(link, verified_lid) }
      ensure_source_link!(chatwoot_phone)
      ensure_verified_link!(verified_lid)
      merge_contact_conversation_aliases!
    end
    @links = nil
  end

  def reconcile_identity_contacts!(verified_lid, network_phone, chatwoot_phone)
    sanitize_contact_email!(@contact)
    contacts = identity_contacts(verified_lid, network_phone, chatwoot_phone)
    @contact.update_columns(phone_number: "+#{chatwoot_phone}", updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    contacts.each do |mergee|
      sanitize_contact_email!(mergee)
      collapse_duplicate_links!(mergee)
      ContactMergeAction.new(account: @channel.account, base_contact: @contact, mergee_contact: mergee).perform
      @contact.reload
    end
  end

  def identity_contacts(verified_lid, network_phone, chatwoot_phone)
    phone_numbers = [@contact.phone_number, "+#{network_phone}", "+#{chatwoot_phone}"].compact_blank.uniq
    contacts = @channel.account.contacts.where(phone_number: phone_numbers).where.not(id: @contact.id).to_a
    contacts.concat(@channel.account.contacts.where(bsuid: verified_lid).where.not(id: @contact.id))
    contacts.concat(
      Contact.joins(contact_inboxes: :inbox)
             .where(account_id: @channel.account.id, inboxes: { account_id: @channel.account.id }, contact_inboxes: { source_id: verified_lid })
             .where.not(id: @contact.id)
    )
    contacts.uniq.sort_by { |contact| contact.phone_number == @contact.phone_number ? 0 : 1 }
  end

  def collapse_duplicate_links!(mergee)
    mergee.contact_inboxes.to_a.each do |mergee_link|
      base_link = @contact.contact_inboxes.find_by(inbox_id: mergee_link.inbox_id, source_id: mergee_link.source_id)
      next if base_link.blank?

      move_link_conversations!(mergee_link, base_link)
      base_link.update!(
        additional_attributes: mergee_link.additional_attributes.deep_merge(base_link.additional_attributes)
      )
      mergee_link.delete
    end
  end

  def sanitize_contact_email!(contact)
    return unless technical_email?(contact)

    contact.update_columns(email: nil, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def stale_lid_links(verified_lid)
    @contact.contact_inboxes.where("source_id LIKE '%@lid'").where.not(source_id: verified_lid).to_a
  end

  def replace_source_links!(old_source_id, verified_source_id)
    return if old_source_id.blank? || old_source_id == verified_source_id

    @contact.contact_inboxes.where(source_id: old_source_id).to_a.each do |link|
      replace_source_link!(link, verified_source_id)
    end
  end

  def normalize_mobile_source_links!(canonical_phone)
    return unless brazilian_mobile_phone?(canonical_phone)

    phone_without_ninth_digit = canonical_phone[0, 4] + canonical_phone[5..]
    replace_source_links!(phone_without_ninth_digit, canonical_phone)
  end

  def replace_source_link!(stale_link, verified_source_id)
    verified_link = stale_link.inbox.contact_inboxes.find_by(source_id: verified_source_id)
    return stale_link.update!(source_id: verified_source_id) if verified_link.blank?

    ensure_link_belongs_to_contact!(verified_link)
    move_link_conversations!(stale_link, verified_link)
    verified_link.update!(
      additional_attributes: stale_link.additional_attributes.deep_merge(verified_link.additional_attributes)
    )
    stale_link.delete
  end

  def move_link_conversations!(source_link, target_link)
    Conversation.where(contact_inbox_id: source_link.id).update_all(contact_inbox_id: target_link.id) # rubocop:disable Rails/SkipsModelValidations
  end

  def ensure_verified_link!(verified_lid)
    ensure_source_link!(verified_lid)
  end

  def ensure_source_link!(source_id)
    verified_link = @channel.inbox.contact_inboxes.find_or_initialize_by(source_id: source_id)
    ensure_link_belongs_to_contact!(verified_link) if verified_link.persisted?
    verified_link.contact = @contact
    verified_link.save!
  end

  def ensure_link_belongs_to_contact!(link)
    return if link.contact_id == @contact.id

    raise Whatsapp::Unoapi::ContactSync::Client::PermanentError,
          "verified LID belongs to inbox contact #{link.contact_id}"
  end

  def merge_contact_conversation_aliases!
    @contact.inboxes.distinct.each do |inbox|
      next unless unoapi_single_conversation_inbox?(inbox)

      merge_inbox_conversation_aliases!(inbox)
    end
  end

  def unoapi_single_conversation_inbox?(inbox)
    inbox.channel.is_a?(Channel::Whatsapp) && inbox.channel.provider == 'unoapi' && inbox.lock_to_single_conversation?
  end

  def merge_inbox_conversation_aliases!(inbox)
    conversations = inbox.conversations.non_group_conversations
                         .where(contact_id: @contact.id, contact_inbox_id: @contact.contact_inboxes.where(inbox_id: inbox.id).select(:id))
                         .to_a
    return if conversations.size <= 1

    target = preferred_conversation(conversations)
    mergees = conversations - [target]
    Message.where(conversation_id: mergees.map(&:id)).update_all(conversation_id: target.id) # rubocop:disable Rails/SkipsModelValidations
    target.update_columns( # rubocop:disable Rails/SkipsModelValidations
      last_activity_at: conversations.filter_map(&:last_activity_at).max,
      updated_at: Time.current
    )
    mergees.each(&:destroy!)
  end

  def preferred_conversation(conversations)
    conversations.select { |conversation| conversation.contact_inbox.source_id.exclude?('@') }
                 .max_by { |conversation| [conversation.last_activity_at, conversation.id] } ||
      conversations.max_by { |conversation| [conversation.last_activity_at, conversation.id] }
  end

  def technical_email?(contact)
    value = contact.email.to_s.strip
    value.present? && (!value.match?(Devise.email_regexp) || value.match?(/@(lid|s\.whatsapp\.net|g\.us|broadcast|newsletter)\z/i))
  end

  def lid
    candidates = [@contact.bsuid, *links.map(&:source_id)]
    candidates.find { |value| value.to_s.match?(/\A\d+@lid\z/) }
  end

  def export_name(phone_number, user_id)
    name = @contact.name.to_s.strip
    return phone_number if name.blank? || name.casecmp?(user_id.to_s) || name.match?(/@\S+\z/i)

    name
  end

  def export_signature(payload)
    Digest::SHA256.hexdigest([payload[:phone_number], payload[:user_id]].compact.join('|'))
  end

  def mark_attempt(payload, status:, remote_contact: nil, error: nil)
    attributes = {
      'signature' => export_signature(payload),
      'status' => status,
      'attempted_at' => Time.current.iso8601(3),
      'phone_number' => remote_contact&.fetch('phone_number', nil) || payload[:phone_number],
      'user_id' => remote_contact&.fetch('user_id', nil) || payload[:user_id],
      'error' => error
    }.compact

    ContactInbox.transaction do
      links.each do |link|
        link.update!(additional_attributes: link.additional_attributes.merge(EXPORT_ATTRIBUTE => attributes))
      end
    end
  end
end
