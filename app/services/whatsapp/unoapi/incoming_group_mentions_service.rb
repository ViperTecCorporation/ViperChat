class Whatsapp::Unoapi::IncomingGroupMentionsService
  MENTION_PATTERN = /(?<![\w@])@((?:[A-Z]{2}\.)?\d{5,})(?:@(?:lid|s\.whatsapp\.net))?(?![\w@])/

  def initialize(account:, content:)
    @account = account
    @content = content
  end

  def perform
    return @content if @content.blank?

    identifiers = @content.scan(MENTION_PATTERN).flatten.uniq
    return @content if identifiers.empty?

    names = resolved_names(identifiers)
    @content.gsub(MENTION_PATTERN) do |mention|
      name = names[Regexp.last_match(1)]
      name.present? ? "@#{escape_name(name)}" : mention
    end
  end

  private

  def resolved_names(identifiers)
    matches = Hash.new { |hash, key| hash[key] = [] }
    matching_contacts(identifiers).each do |contact|
      keys = [contact.bsuid.to_s.sub(/@(?:lid|s\.whatsapp\.net)\z/, ''), contact.phone_number.to_s.delete_prefix('+')]
      (keys.uniq & identifiers).each { |key| matches[key] << contact }
    end
    matches.transform_values { |items| items.one? ? items.first.name : nil }
  end

  def matching_contacts(identifiers)
    aliases = identifiers.flat_map { |identifier| [identifier, "#{identifier}@lid", "#{identifier}@s.whatsapp.net"] }
    phones = identifiers.flat_map { |identifier| [identifier, "+#{identifier}"] }
    @account.contacts.where(bsuid: aliases).or(@account.contacts.where(phone_number: phones))
  end

  def escape_name(name)
    name.gsub(/[\\`*_\[\]{}()<>#!|]/) { |character| "\\#{character}" }
  end
end
