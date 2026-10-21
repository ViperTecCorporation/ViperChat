class Voip::DirectoryService
  PER_PAGE = 15
  PHONE_SQL = "regexp_replace(contacts.phone_number, '[^0-9]', '', 'g')".freeze

  def initialize(account:, user:, membership:, service:)
    @account = account
    @user = user
    @membership = membership
    @service = service
  end

  def directory(kind:, search:, page:)
    raise ArgumentError, 'invalid_directory_kind' unless %w[contacts extensions].include?(kind)

    scope = kind == 'contacts' ? contacts : extensions
    scope = search_scope(scope, kind, search) if search.present?
    total = scope.count
    rows = scope.order(kind == 'contacts' ? 'contacts.name, contacts.id' : 'users.name, voip_agent_extensions.id')
                .limit(PER_PAGE).offset((page - 1) * PER_PAGE)
    { items: rows.map { |row| kind == 'contacts' ? contact_payload(row) : agent_payload(row) }, total: total, page: page }
  end

  def identity(address)
    identities([address])[address.to_s]
  end

  # Resolve a page in two eager-loaded queries, not one query per call/favorite.
  def identities(addresses)
    addresses = addresses.map(&:to_s).uniq
    agents = extensions.where(extension: addresses).to_a.group_by(&:extension)
    matches = telephone_matches(addresses)
    addresses.index_with { |address| resolved_identity(agents[address] || [], matches[phone(address)] || []) }
  end

  def matching_calls(scope, query)
    named_contacts = Search::TextQuery.apply(contacts, ['contacts.name'], query)
    phones = named_contacts.reselect(Arel.sql(PHONE_SQL)).unscope(:includes)
    named_extensions = Search::TextQuery.apply(extensions, ['users.name'], query).reselect(:extension).unscope(:includes)
    eligible = scope.where(voip_agent_extensions: { voip_service_id: @service.id })
    eligible.where("regexp_replace(voip_calls.remote_address, '[^0-9]', '', 'g') IN (?)", phones)
            .where("voip_calls.remote_address ~ '^[+]?[0-9 () .-]+$'")
            .or(eligible.where(remote_address: named_extensions))
  end

  def contacts
    return Contact.none unless Pundit.policy!(context, Contact).search?

    scope = @account.contacts.where("contacts.phone_number ~ '^[+]?[0-9 () .-]+$'")
                    .where("length(#{PHONE_SQL}) BETWEEN 7 AND 15")
                    .where("coalesce(contacts.email, '') NOT LIKE '%@g.us'")
                    .where("coalesce(contacts.identifier, '') NOT LIKE '%@g.us'")
                    .where("coalesce(contacts.additional_attributes->>'is_group', 'false') != 'true'")
                    .where("coalesce(contacts.additional_attributes->>'group', 'false') != 'true'")
    visibility = Search::ConversationVisibilityService.new(current_user: @user, current_account: @account)
    scope = visibility.contacts(scope) if visibility.assignment_restricted?
    scope.includes(avatar_attachment: :blob)
  end

  def extensions
    return VoipAgentExtension.none unless @service.available_to?(@membership)

    scope = @service.voip_agent_extensions.joins(account_user: :user).where(account_users: { account_id: @account.id })
    scope = scope.where(account_users: { user_id: @service.allowed_user_ids }).or(scope.where(account_users: { role: :administrator })) \
      if @service.allowed_user_ids.present?
    scope.includes(account_user: { user: { avatar_attachment: :blob } })
  end

  private

  def telephone_matches(addresses)
    phones = addresses.filter_map { |address| phone(address) }.uniq
    return {} if phones.empty?

    contacts.where("#{PHONE_SQL} IN (?)", phones).to_a.group_by { |contact| phone(contact.phone_number) }
  end

  def resolved_identity(agents, matches)
    return agent_payload(agents.first) if agents.one?
    return unless agents.empty? && matches.one?

    contact_payload(matches.first)
  end

  def context
    { user: @user, account: @account, account_user: @membership }
  end

  def phone(address)
    value = address.to_s
    return unless value.match?(/\A\+?[\d ().-]+\z/)

    digits = value.gsub(/\D/, '')
    digits if digits.length.between?(7, 15)
  end

  def search_scope(scope, kind, query)
    columns = kind == 'contacts' ? %w[contacts.name contacts.phone_number] : %w[users.name voip_agent_extensions.extension]
    result = Search::TextQuery.apply(scope, columns, query)
    return result unless kind == 'contacts' && query.match?(/\A[+\d\s().-]+\z/) && query.match?(/\d/)

    result.or(scope.where("#{PHONE_SQL} LIKE ?", "%#{query.gsub(/\D/, '')}%"))
  end

  def contact_payload(contact)
    { kind: 'contact', id: contact.id, contact_id: contact.id, name: contact.name, address: contact.phone_number,
      avatar_url: contact.avatar_url, service_id: @service.id }
  end

  def agent_payload(binding)
    user = binding.account_user.user
    { kind: 'agent', id: user.id, user_id: user.id, name: user.name, address: binding.extension,
      avatar_url: user.avatar_url, service_id: @service.id }
  end
end
