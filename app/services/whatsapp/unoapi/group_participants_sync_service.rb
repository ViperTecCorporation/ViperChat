class Whatsapp::Unoapi::GroupParticipantsSyncService
  def initialize(inbox:, conversation:, group_source_id: nil)
    @inbox = inbox
    @channel = inbox.channel
    @conversation = conversation
    @group_source_id = group_source_id.presence || conversation.group_source_id
  end

  def perform
    return :missing_group unless @conversation.group? && @group_source_id.present?
    return :unsupported_provider unless @channel.respond_to?(:provider_service) && @channel.provider == 'unoapi'

    response = @channel.provider_service.group_participants(@group_source_id)
    return cache_miss if response.code.to_i == 404

    unless response.success?
      Rails.logger.error("[WHATSAPP][GROUP] participants sync failed group_source_id=#{@group_source_id} status=#{response.code}")
      return :failed
    end

    sync_payload(response.parsed_response.with_indifferent_access)
    :ok
  end

  private

  def cache_miss
    Rails.logger.info("[WHATSAPP][GROUP] participants sync cache_miss group_source_id=#{@group_source_id}")
    :cache_miss
  end

  def sync_payload(payload)
    participants = Array(payload[:participants]).map(&:with_indifferent_access)

    update_group_metadata(payload[:group] || {})
    participants.each { |participant| sync_participant(participant) }
    @conversation.group_session_admin = session_admin?(participants)
    @conversation.update!(group_contacts_synced_at: Time.current)
  end

  def update_group_metadata(group)
    attrs = {
      group_title: group[:subject].presence,
      group_description: group[:description].presence,
      group_invite_link: group[:invite_link].presence,
      group_join_approval_mode: group[:join_approval_mode].presence,
      group_created_at_external: external_time(group[:created_at])
    }.compact
    attrs[:group_suspended] = group[:suspended] unless group[:suspended].nil?

    if group[:picture].present?
      @conversation.additional_attributes ||= {}
      @conversation.additional_attributes['group_picture'] = group[:picture]
    end

    @conversation.assign_attributes(attrs)
    @conversation.save! if @conversation.changed?
  end

  def sync_participant(participant)
    source_id = participant_source_id(participant)
    return if source_id.blank?

    sanitize_existing_contact_email(source_id, participant)

    contact_inbox = ContactInboxWithContactBuilder.new(
      source_id: source_id,
      inbox: @inbox,
      contact_attributes: contact_attributes(participant, source_id)
    ).perform

    group_contact = @conversation.group_contacts.find_or_initialize_by(contact: contact_inbox.contact)
    group_contact.account_id = @conversation.account_id
    group_contact.metadata = participant_metadata(participant, source_id)
    group_contact.save!
  end

  def sanitize_existing_contact_email(source_id, participant)
    contact = existing_participant_contact(source_id, participant)
    return if contact.blank? || contact.email.blank?
    return if valid_contact_email?(contact.email)

    Rails.logger.info("[WHATSAPP][GROUP] clearing invalid participant email contact_id=#{contact.id} email=#{contact.email}")
    contact.update_columns(email: nil, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def existing_participant_contact(source_id, participant)
    @inbox.contact_inboxes.find_by(source_id: source_id)&.contact ||
      Contact.find_by(account_id: @conversation.account_id, bsuid: participant_bsuid(participant))
  end

  def valid_contact_email?(email)
    email.match?(Devise.email_regexp) || email.end_with?('@lid') || email.end_with?('@g.us')
  end

  def contact_attributes(participant, source_id)
    attrs = {
      name: participant_name(participant, source_id),
      avatar_url: participant[:picture].presence,
      bsuid: participant_bsuid(participant),
      whatsapp_username: participant[:username].presence
    }.compact

    unless source_id.include?('@')
      phone = normalized_phone((participant[:wa_id].presence || source_id).to_s.gsub(/\D/, ''))
      attrs[:phone_number] = "+#{phone}" if phone.present?
    end

    attrs
  end

  def participant_name(participant, source_id)
    participant[:name].presence ||
      participant[:pushname].presence ||
      participant[:username].presence ||
      participant[:wa_id].presence ||
      participant_bsuid(participant) ||
      source_id
  end

  def participant_metadata(participant, source_id)
    {
      jid: participant[:jid].presence || source_id,
      wa_id: participant[:wa_id].presence,
      lid: participant[:lid].presence,
      user_id: participant[:user_id].presence,
      username: participant[:username].presence,
      role: participant[:role].presence,
      is_admin: participant[:is_admin],
      picture: participant[:picture].presence
    }.compact
  end

  def participant_source_id(participant)
    return participant[:wa_id] if participant[:wa_id].present?
    return participant_bsuid(participant) if participant_bsuid(participant).present?
    return participant[:jid] if participant[:jid].to_s.include?('@lid')

    participant[:jid].to_s.gsub(/\D/, '').presence
  end

  def participant_bsuid(participant)
    participant[:user_id].presence || participant[:lid].presence
  end

  def session_admin?(participants)
    session_participant = participants.find { |participant| session_participant?(participant) }
    return false if session_participant.blank?

    ActiveModel::Type::Boolean.new.cast(session_participant[:is_admin]) ||
      session_participant[:role].to_s.casecmp('admin').zero? ||
      session_participant[:role].to_s.casecmp('superadmin').zero?
  end

  def session_participant?(participant)
    identifiers = [
      participant[:wa_id],
      participant[:jid],
      participant[:lid],
      participant[:user_id],
      participant_source_id(participant)
    ].compact.map(&:to_s)

    session_identifiers.any? do |session_identifier|
      identifiers.any? { |identifier| identifier == session_identifier || identifier.gsub(/\D/, '') == session_identifier.gsub(/\D/, '') }
    end
  end

  def session_identifiers
    @session_identifiers ||= [
      @channel.provider_config['business_account_id'],
      @channel.provider_config['phone_number_id'],
      @channel.phone_number
    ].compact.map(&:to_s).flat_map do |identifier|
      digits = identifier.gsub(/\D/, '')
      [identifier, digits, normalized_phone(digits)].compact
    end.uniq
  end

  def external_time(value)
    return if value.blank?
    return Time.zone.at(value.to_i) if value.to_s.match?(/\A\d+\z/)

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def normalized_phone(phone)
    return phone unless phone.start_with?('55') && phone.length == 12

    "#{phone[0..3]}9#{phone[4..]}"
  end
end
