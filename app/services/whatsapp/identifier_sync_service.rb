class Whatsapp::IdentifierSyncService
  pattr_initialize [:contact_inbox!, :contact]

  def perform(source_ids: [], username: nil, phone_number: nil)
    source_ids = normalize_source_ids(source_ids)
    replace_stale_unoapi_lids(source_ids)
    create_contact_inboxes(source_ids)
    update_contact(username, phone_number)
  end

  private

  def normalize_source_ids(source_ids)
    return source_ids unless unoapi_inbox?

    source_ids.map { |source_id| Whatsapp::Unoapi::LidIdentity.canonicalize(source_id) || source_id }
  end

  def replace_stale_unoapi_lids(source_ids)
    return unless unoapi_inbox?

    canonical_lid = canonical_lid_from(source_ids)
    return if canonical_lid.blank?

    canonical_link = inbox.contact_inboxes.find_by(source_id: canonical_lid)
    stale_lid_links(canonical_lid).find_each do |stale_link|
      canonical_link = replace_stale_lid_link(stale_link, canonical_link, canonical_lid)
    end
  end

  def replace_stale_lid_link(stale_link, canonical_link, canonical_lid)
    if canonical_link.present?
      stale_link.conversations.update_all(contact_inbox_id: canonical_link.id) # rubocop:disable Rails/SkipsModelValidations
      stale_link.destroy!
      canonical_link
    else
      stale_link.update!(source_id: canonical_lid)
      stale_link
    end
  rescue ActiveRecord::RecordNotUnique
    canonical_link = inbox.contact_inboxes.find_by(source_id: canonical_lid)
    retry
  end

  def stale_lid_links(canonical_lid)
    inbox.contact_inboxes.where(contact: synced_contact).where("source_id ILIKE '%@lid'").where.not(source_id: canonical_lid)
  end

  def canonical_lid_from(source_ids)
    source_ids.filter_map { |source_id| Whatsapp::Unoapi::LidIdentity.canonicalize(source_id) }.first
  end

  def unoapi_inbox?
    inbox.channel_type == 'Channel::Whatsapp' && inbox.channel.provider == 'unoapi'
  end

  def create_contact_inboxes(source_ids)
    source_ids.compact_blank.uniq.each do |source_id|
      next if inbox.contact_inboxes.exists?(source_id: source_id)

      inbox.contact_inboxes.create!(contact: synced_contact, source_id: source_id)
    rescue ActiveRecord::RecordNotUnique
      # A concurrent webhook (e.g. a status update bypassing the per-contact
      # mutex) just inserted the same (inbox_id, source_id). Treat it as a
      # no-op instead of falling through to ContactInboxBuilder's retry path,
      # which would scramble the freshly-written row.
    end
  end

  def update_contact(username, phone_number)
    return if synced_contact.blank?

    update_contact_phone_number(phone_number)
    update_contact_username(username)
  end

  def update_contact_phone_number(phone_number)
    phone_number = phone_number.presence
    return if phone_number.blank? || synced_contact.phone_number.present?
    return if synced_contact.account.contacts.where(phone_number: phone_number).where.not(id: synced_contact.id).exists?

    synced_contact.update!(phone_number: phone_number)
  end

  def update_contact_username(username)
    username = normalize_username(username)
    return if username.blank?

    synced_contact.update!(additional_attributes: additional_attributes_with_username(username))
  end

  def synced_contact
    @synced_contact ||= contact || contact_inbox.contact
  end

  def inbox
    @inbox ||= contact_inbox.inbox
  end

  def normalize_username(value)
    value.to_s.sub(/\A@+/, '').presence
  end

  def additional_attributes_with_username(username)
    attributes = synced_contact.additional_attributes.deep_dup
    social_profiles = attributes['social_profiles'] || {}
    social_profiles['whatsapp'] = username

    attributes.merge(
      'social_profiles' => social_profiles,
      'social_whatsapp_user_name' => username
    )
  end
end
