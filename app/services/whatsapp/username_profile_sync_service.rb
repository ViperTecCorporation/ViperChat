# A username is mutable profile data, never an identifier or correlation key.
class Whatsapp::UsernameProfileSyncService
  include Whatsapp::AvatarMetadata

  def initialize(inbox:, value:, outgoing_echo: false)
    @inbox = inbox
    @value = value.to_h.with_indifferent_access
    @outgoing_echo = outgoing_echo
  end

  def perform
    return unless @inbox.channel.provider == 'whatsapp_cloud' && @inbox.account.active?

    events.reject { |event| Whatsapp::GroupEventPolicy.group_record?(event) }.each { |event| sync_profile(event) }
  end

  private

  def sync_profile(event)
    profile = matching_profile(event)
    message = message_for(event[:id]) if profile
    return unless eligible_message?(message)

    contact = message.conversation.contact
    contact.with_lock do
      next unless proven_participant?(contact, event)

      sync_username(contact, message, profile)
      Avatar::AvatarFromUrlJob.enqueue_if_needed(contact, profile.dig(:profile, :picture), avatar_metadata_from(profile, profile[:profile]))
    end
  end

  def sync_username(contact, message, profile)
    return if profile.dig(:profile, :username).blank?

    # Preserve the canonical field's raw @ format; only social mirrors normalize it.
    contact.whatsapp_username = profile.dig(:profile, :username).to_s.strip
    Whatsapp::IdentifierSyncService.new(contact_inbox: message.conversation.contact_inbox, contact: contact)
                                   .perform(username: profile.dig(:profile, :username))
  end

  def events
    Array(@value[:statuses].presence || @value[:message_echoes].presence || @value[:messages])
  end

  def outgoing?
    @value[:statuses].present? || @value[:message_echoes].present? || @outgoing_echo
  end

  def participant(event)
    if @value[:statuses].present?
      [event[:recipient_user_id].presence, event[:recipient_id].presence]
    elsif outgoing?
      [event[:to_user_id].presence, event[:to].presence]
    else
      [event[:from_user_id].presence, event[:from].presence]
    end
  end

  def matching_profile(event)
    matches = Array(@value[:contacts]).select { |contact| profile_matches?(contact, event) }
    matches.sole if matches.one?
  end

  def profile_matches?(contact, event)
    return false if contact.dig(:profile, :username).blank? && contact.dig(:profile, :picture).blank?

    user_id, phone = participant(event)
    return same_phone?(contact[:wa_id], phone) unless user_id

    contact[:user_id] == user_id && (phone.blank? || same_phone?(contact[:wa_id], phone))
  end

  def message_for(external_id)
    return if external_id.blank?

    direct = @inbox.messages.where(account_id: @inbox.account_id, source_id: external_id).to_a
    return direct.sole if direct.one?
    return if direct.any?

    mapped_message(external_id)
  end

  def mapped_message(external_id)
    identity = WhatsappMessageIdentity.find_by(inbox: @inbox, account_id: @inbox.account_id, external_id: external_id)
    return unless identity&.observations&.dig('meta_id_adapter', 'status') == 'recognized'

    link = WhatsappInboxLink.for_inbox(@inbox)
    candidate = Whatsapp::UnifiedMessageIngestionService.message_for(identity)
    candidate if link && candidate && link.covers?(candidate.inbox)
  end

  def eligible_message?(message)
    return false unless same_account?(message)

    message.message_type == (outgoing? ? 'outgoing' : 'incoming') && !message.private? &&
      !message.web_attendance? && !message.conversation.group?
  end

  def same_account?(message)
    message && message.account_id == @inbox.account_id && message.conversation.account_id == @inbox.account_id
  end

  def proven_participant?(contact, event)
    return false unless contact.account_id == @inbox.account_id

    user_id, phone = participant(event)
    bsuid_matches = user_id.blank? || contact.bsuid == user_id || proven_bsuid_alias?(contact, event, user_id)
    bsuid_matches && (phone.blank? || contact_phone_matches?(contact, phone))
  end

  def proven_bsuid_alias?(contact, event, user_id)
    return false unless contact.contact_inboxes.exists?(inbox_id: @inbox.id, source_id: user_id)

    identity = WhatsappMessageIdentity.find_by(inbox: @inbox, account_id: @inbox.account_id, external_id: event[:id])
    observations = identity&.observations || {}
    return false if observations['conflicting_observations'].present?
    return false unless receipt_role_matches?(observations, user_id)

    key = outgoing? ? 'to_user_id' : 'from_user_id'
    observations.dig('participants', key) == user_id
  end

  def receipt_role_matches?(observations, user_id)
    return true if @value[:statuses].blank?

    receipt = observations['receipt_participants'] || observations['participants'] || {}
    receipt['recipient_user_id'] == user_id
  end

  def contact_phone_matches?(contact, phone)
    variants = Whatsapp::ContactIdentityLock.phone_variants(phone)
    variants.present? && (same_phone?(contact.phone_number, phone) ||
      contact.contact_inboxes.exists?(inbox_id: @inbox.id, source_id: variants))
  end

  def same_phone?(left, right)
    normalized = Whatsapp::InboxLinkPhoneService.normalize(left)
    normalized.present? && normalized == Whatsapp::InboxLinkPhoneService.normalize(right)
  end
end
