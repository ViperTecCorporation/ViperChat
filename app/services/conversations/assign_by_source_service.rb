class Conversations::AssignBySourceService
  def initialize(account:, inbox_phone_number:, contact_identifier:, team_name:)
    @account = account
    @inbox_phone_number = inbox_phone_number.to_s.strip
    @contact_identifier = contact_identifier.to_s.strip
    @team_name = team_name.to_s.gsub(/[[:cntrl:]]/, '').strip.downcase
  end

  def perform
    inbox = find_inbox
    contact = find_contact(inbox)
    conversation = inbox.conversations.non_group_conversations
                        .where(contact: contact)
                        .order(last_activity_at: :desc, id: :desc)
                        .first!

    {
      conversation: conversation,
      inbox: inbox,
      team: find_team
    }
  end

  private

  def find_inbox
    channel = Channel::Whatsapp.where(account: @account, provider: 'unoapi', phone_number: inbox_phone_candidates).first!
    @account.inboxes.find_by!(channel: channel)
  end

  def find_contact(inbox)
    contact_inbox = inbox.contact_inboxes.where(source_id: contact_identifier_candidates).first
    return contact_inbox.contact if contact_inbox

    contacts = @account.contacts.where(phone_number: contact_phone_candidates)
                       .or(@account.contacts.where(bsuid: contact_identifier_candidates))
                       .or(@account.contacts.where(whatsapp_username: contact_identifier_candidates))

    inbox.contact_inboxes.find_by!(contact_id: contacts.select(:id)).contact
  end

  def find_team
    exact_match = @account.teams.find_by(name: @team_name)
    return exact_match if exact_match

    escaped_name = ActiveRecord::Base.sanitize_sql_like(@team_name)
    matches = @account.teams.where('name ILIKE ?', "%#{escaped_name}%").limit(2).to_a
    return matches.first if matches.one?

    raise ActiveRecord::RecordNotFound, 'Could not find a unique team'
  end

  def inbox_phone_candidates
    digits = @inbox_phone_number.gsub(/\D/, '')
    [@inbox_phone_number, digits, prefixed_phone(digits)].compact_blank.uniq
  end

  def contact_identifier_candidates
    digits = @contact_identifier.gsub(/\D/, '')
    canonical_digits = normalize_brazilian_mobile(digits)

    [@contact_identifier, digits, canonical_digits, prefixed_phone(digits), prefixed_phone(canonical_digits)].compact_blank.uniq
  end

  def contact_phone_candidates
    contact_identifier_candidates.grep(/\A\+?\d+\z/)
  end

  def normalize_brazilian_mobile(digits)
    return digits unless digits.start_with?('55') && digits.length == 12

    "#{digits[0..3]}9#{digits[4..]}"
  end

  def prefixed_phone(digits)
    "+#{digits}" if digits.present?
  end
end
