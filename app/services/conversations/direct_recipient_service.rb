class Conversations::DirectRecipientService
  def initialize(account:, inbox:, user:, recipient:)
    @account = account
    @inbox = inbox
    @user = user
    @recipient = recipient
  end

  def perform
    validate_access!
    identity = normalized_identity
    @account.with_lock do
      contact = find_contact(identity)
      contact ||= @account.contacts.create!(identity.merge(name: identity.values.first))
      resolve_contact_inbox(contact, identity)
    end
  end

  private

  def validate_access!
    raise ActionController::BadRequest, 'WhatsApp inbox required' unless @inbox&.whatsapp?
    return unless @account.feature_enabled?('hide_contacts_for_agent')
    return if @account.account_users.find_by!(user: @user).administrator?

    raise Pundit::NotAuthorizedError
  end

  def visibility
    @visibility ||= Search::ConversationVisibilityService.new(current_user: @user, current_account: @account)
  end

  def find_contact(identity)
    contacts = matching_contacts(identity).to_a
    raise ActionController::BadRequest, 'Ambiguous recipient' if contacts.length > 1

    contact = contacts.first
    raise Pundit::NotAuthorizedError if contact && !visibility.contacts(@account.contacts.where(id: contact.id)).exists?

    contact
  end

  def resolve_contact_inbox(contact, identity)
    source_id = identity[:bsuid] || identity[:phone_number].delete_prefix('+')
    existing = contact.contact_inboxes.find_by(inbox: @inbox)
    latest = existing.conversations.order(created_at: :desc).first if existing
    raise Pundit::NotAuthorizedError if latest && !visibility.conversations.exists?(id: latest.id)

    existing || ContactInboxBuilder.new(contact: contact, inbox: @inbox, source_id: source_id).perform
  end

  def normalized_identity
    bsuid = @recipient[:bsuid].to_s.strip.delete_prefix('@')
    return { bsuid: normalized_bsuid(bsuid) } if bsuid.present?

    { phone_number: normalized_phone }
  end

  def normalized_bsuid(bsuid)
    raise ActionController::BadRequest, 'Invalid BSUID/LID' unless bsuid.match?(/\A(?:[A-Z]{2}\.)?\d{5,}(?:@lid)?\z/)
    raise ActionController::BadRequest, 'Unsupported BSUID inbox' unless %w[unoapi whatsapp_cloud].include?(@inbox.channel.provider)

    @inbox.channel.provider == 'unoapi' && bsuid.match?(/\A\d+\z/) ? "#{bsuid}@lid" : bsuid
  end

  def normalized_phone
    raw = @recipient[:phone_number].to_s.strip
    raise ActionController::BadRequest, 'Invalid phone number' unless raw.match?(/\A\+?[\d\s().-]+\z/)

    digits = raw.gsub(/\D/, '')
    raise ActionController::BadRequest, 'Missing area or country code' unless raw.start_with?('+') || digits.match?(/\A(?:\d{10,11}|55\d{10,11})\z/)

    digits = "55#{digits}" if !raw.start_with?('+') && [10, 11].include?(digits.length)
    phone = "+#{digits}"
    raise ActionController::BadRequest, 'Invalid phone number or missing area code' unless Phonelib.valid?(phone)

    phone
  end

  def matching_contacts(identity)
    value = identity.values.first.delete_prefix('+').delete_suffix('@lid')
    aliases = [value, "#{value}@lid", "#{value}@s.whatsapp.net"]
    linked_ids = @inbox.contact_inboxes.where(source_id: aliases).select(:contact_id)
    @account.contacts.where(bsuid: aliases)
            .or(@account.contacts.where(phone_number: "+#{value}"))
            .or(@account.contacts.where(id: linked_ids))
  end
end
