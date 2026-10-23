class Whatsapp::PartnerInboxReportService
  class InvalidParameters < StandardError; end

  MAX_ROWS = 100_000
  PROVIDERS = %w[unoapi whatsapp_cloud unknown].freeze

  def initialize(account:, params:)
    @account = account
    @params = params.to_h.stringify_keys
    @timezone = @params['timezone'].presence || @account.reporting_timezone.presence || Time.zone.tzinfo.name
    @zone = ActiveSupport::TimeZone[@timezone || 'UTC']
    raise InvalidParameters, 'invalid_timezone' unless @zone

    parse_period
    @rates = parse_rates
  rescue ArgumentError, KeyError, TypeError
    raise InvalidParameters, 'invalid_parameters'
  end

  def perform
    available_pairs = WhatsappInboxLink.where(account_id: @account.id)
                                       .includes(primary_inbox: :channel, secondary_inbox: :channel).order(:id).to_a
    pairs = selected_pairs(available_pairs)
    rows = load_rows(pairs)
    selected = rows.select { |row| row[:created_at] >= @since && row[:created_at] < @until }
    report_metadata.merge(
      available_pairs: available_pairs.map { |link| { id: link.id, name: link.primary_inbox.name, partner_name: link.secondary_inbox.name } },
      pairs: pairs.map { |link| pair_summary(link, selected) }, totals: counters(selected),
      daily: daily_counts(selected), simulation: simulation(rows)
    )
  rescue ArgumentError
    raise InvalidParameters, 'invalid_parameters'
  end

  private

  def parse_period
    @since = @zone.parse(Date.iso8601(@params.fetch('from')).to_s)
    @until = @zone.parse((Date.iso8601(@params.fetch('to')) + 1.day).to_s)
    raise InvalidParameters, 'invalid_period' unless @until > @since && (@until.to_date - @since.to_date) <= 366

    @ad_days = Integer(@params.fetch('ad_window_days', 7))
    raise InvalidParameters, 'invalid_ad_window' unless [3, 7].include?(@ad_days)
  end

  def parse_rates
    Whatsapp::PartnerCostSimulationService::CATEGORIES.index_with do |category|
      value = @params["#{category}_rate"].presence
      next if value.nil?

      rate = BigDecimal(value.to_s)
      raise InvalidParameters, 'invalid_rate' unless rate.finite? && rate >= 0 && rate <= 1_000_000

      rate
    end
  end

  def report_metadata
    {
      from: @since.iso8601, to_exclusive: @until.iso8601, timezone: @zone.tzinfo.name,
      simulation_only: true, timezone_confirmed: @timezone.present?, ad_window_days: @ad_days, monthly_allowance: 1000
    }
  end

  def simulation(rows)
    comparison = Whatsapp::PartnerCostComparisonService.new(timezone: @timezone, rates: @rates, ad_window_days: @ad_days)
    comparison.perform(rows: rows, since: @since, until_time: @until).tap do |result|
      result[:ad_leads] = Whatsapp::AdLeadPresenter.new(account: @account).perform(result[:ad_leads])
    end
  end

  def selected_pairs(pairs)
    return pairs if @params['link_id'].blank?

    id = Integer(@params['link_id'])
    pairs.select { |link| link.id == id }
  end

  def daily_counts(rows)
    Whatsapp::PartnerInboxReportCountersService.daily(rows, zone: @zone, since: @since, until_time: @until)
  end

  def load_rows(pairs)
    prepare_channels(pairs)
    return [] if @channels.empty?

    messages = report_messages
    ids = messages.map(&:id)
    link_ids = pairs.map(&:id)
    @canonical = canonical_ids(ids, link_ids)
    @observations = observations(ids)
    @contacts = @account.conversations.where(id: messages.map(&:conversation_id)).pluck(:id, :contact_id).to_h
    messages.filter_map { |message| build_row(message) if reportable?(message) }
  end

  def prepare_channels(pairs)
    inboxes = pairs.flat_map { |link| [link.primary_inbox, link.secondary_inbox] }.uniq(&:id).index_by(&:id)
    @phones = inboxes.transform_values { |inbox| Whatsapp::InboxLinkPhoneService.normalize(inbox.channel.phone_number) }
    @channels = inboxes.transform_values(&:channel)
  end

  def reportable?(message)
    return false if @canonical[message.id] && @canonical[message.id] != message.id

    !message.content_attributes['whatsapp_history_import'] && !message.content_attributes['is_reaction']
  end

  def report_messages
    # Read the whole first billing month, plus referral/customer-window evidence preceding it.
    scope = @account.messages.where(inbox_id: @channels.keys, private: false, message_type: %i[incoming outgoing], delivery_destination: 'channel')
                    .where(created_at: (@since.beginning_of_month - (@ad_days + 1).days)...@until)
                    .where.not(content_type: :voice_call)
    raise InvalidParameters, 'period_too_large' if scope.limit(MAX_ROWS + 1).count > MAX_ROWS

    scope.select(:id, :inbox_id, :conversation_id, :message_type, :created_at, :source_id, :status,
                 :content_attributes, :additional_attributes).order(:created_at, :id).to_a
  end

  def received_providers(message)
    providers = @observations.fetch(message.id, []).filter_map do |provider, observation|
      provider if observation['direction'] == 'incoming'
    end.uniq
    providers << @channels.fetch(message.inbox_id).provider if providers.empty? && message.content_attributes['whatsapp_unified_message_id'].blank?
    providers
  end

  def build_row(message)
    attrs = message.content_attributes
    received = message.incoming? ? received_providers(message) : []
    provider = message.incoming? ? received.first || 'unknown' : outgoing_provider(message, attrs)
    { id: message.id, inbox_id: message.inbox_id, created_at: message.created_at, direction: message.message_type,
      business_phone: @phones.fetch(message.inbox_id), contact_id: @contacts.fetch(message.conversation_id),
      provider: provider, received_providers: received, delivered: delivered?(message, attrs, provider),
      template: message.additional_attributes['template_params'].present?, category: template_category(message, provider),
      ad_referral: attrs.dig('referral', 'source_type') == 'ad' && attrs.dig('referral', 'source_id').present?,
      ad_source_id: attrs.dig('referral', 'source_id'), has_click_id: attrs.dig('referral', 'ctwa_clid').present? }
  end

  def observations(ids)
    result = Hash.new { |hash, key| hash[key] = [] }
    WhatsappMessageIdentityLink.joins(:whatsapp_message_identity).where(message_id: ids)
                               .where(whatsapp_message_identities: { account_id: @account.id })
                               .pluck(:message_id, 'whatsapp_message_identities.provider',
                                      'whatsapp_message_identities.observations').each do |id, provider, attrs|
      result[id] << [provider, attrs]
    end
    canonical = 'COALESCE(whatsapp_unified_messages.message_id, whatsapp_unified_message_aliases.message_id)'
    WhatsappUnifiedMessageAlias.left_joins(:whatsapp_unified_message).joins(:whatsapp_message_identity)
                               .where(whatsapp_message_identities: { account_id: @account.id, inbox_id: @channels.keys })
                               .where("#{canonical} IN (?)", ids)
                               .pluck(Arel.sql(canonical), 'whatsapp_message_identities.provider',
                                      'whatsapp_message_identities.observations').each do |id, provider, attrs|
      result[id] << [provider, attrs]
    end
    result
  end

  def canonical_ids(ids, link_ids)
    rows = WhatsappUnifiedMessage.where(whatsapp_inbox_link_id: link_ids).where.not(message_id: nil)
    canonical = rows.where(message_id: ids).pluck(:message_id).index_with(&:itself)
    WhatsappUnifiedMessageAlias.joins(:whatsapp_unified_message)
                               .where(message_id: ids, whatsapp_unified_messages: { whatsapp_inbox_link_id: link_ids })
                               .pluck(:message_id, 'whatsapp_unified_messages.message_id').each do |id, target|
      canonical[id] = target if target
    end
    canonical
  end

  def template_category(message, provider)
    template = message.additional_attributes['template_params']
    return if template.blank?

    channel = template_channel(message.inbox_id, provider)
    cached = Array(channel&.message_templates).find { |item| item.values_at('name', 'language') == template.values_at('name', 'language') }
    (template['category'].presence || cached&.[]('category'))&.downcase
  end

  def template_channel(inbox_id, provider)
    channel_id = @channels.keys.find { |id| @channels[id].provider == provider && @phones[id] == @phones[inbox_id] }
    @channels[channel_id]
  end

  def outgoing_provider(message, attrs)
    provider = attrs.dig('whatsapp_transport', 'provider')
    return provider if PROVIDERS.include?(provider)

    providers = @observations.fetch(message.id, []).select do |_, observation|
      observation.values_at('origin', 'direction') == %w[api_response outgoing]
    end.map(&:first).uniq
    providers.one? ? providers.first : 'unknown'
  end

  def delivered?(message, attrs, provider)
    outcome = attrs.dig('whatsapp_delivery', provider)
    return %w[delivered read].include?(outcome['state']) && outcome['origin'] != 'echo' if outcome.present?

    %w[delivered read].include?(message.status)
  end

  def counters(rows)
    Whatsapp::PartnerInboxReportCountersService.count(rows)
  end

  def pair_summary(link, rows)
    { id: link.id, name: link.primary_inbox.name, partner_name: link.secondary_inbox.name, enabled: link.enabled,
      business_phone: Whatsapp::InboxLinkPhoneService.normalize(link.primary_inbox.channel.phone_number),
      counts: counters(rows.select { |row| [link.primary_inbox_id, link.secondary_inbox_id].include?(row[:inbox_id]) }) }
  end
end
