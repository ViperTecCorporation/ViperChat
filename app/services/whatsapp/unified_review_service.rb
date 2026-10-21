# Administrative review never sends a message, invents an alias or changes a
# delivery receipt. An acknowledgement is a separate, append-only audit record.
class Whatsapp::UnifiedReviewService
  class Conflict < StandardError; end

  PAGE_SIZE = 25
  KINDS = %w[event delivery media reservation].freeze

  def initialize(link:, actor:)
    @link = link
    @actor = actor
  end

  def list(page: nil, kind: nil, status: nil)
    scopes = listing_scopes(kind, status)
    total = scopes.values.sum(&:count)
    total_pages = (total.to_f / PAGE_SIZE).ceil
    page = page.to_i.clamp(1, [total_pages, 1].max)
    rows = listing_rows(scopes, page)
    items = rows.drop((page - 1) * PAGE_SIZE).first(PAGE_SIZE).map { |type, record| serialize(type, record) }
    { items: items, meta: { page: page, total: total, total_pages: total_pages } }
  end

  def act(id:, action:, version:)
    kind, subject_id = parse_id(id)
    raise ArgumentError unless %w[recheck acknowledge].include?(action)

    record = scope(kind).find(subject_id)
    record.with_lock do
      @link.reload
      raise Conflict unless version.present? && ActiveSupport::SecurityUtils.secure_compare(version.to_s, revision(kind, record))
      raise Conflict unless actions(kind, record).fetch(action.to_sym)

      recheck(kind, record) if action == 'recheck'
      WhatsappUnifiedReviewAction.create!(whatsapp_inbox_link: @link, actor: @actor, subject_kind: kind,
                                          subject_id: record.id, subject_updated_at: record.updated_at, action: action)
      serialize(kind, record)
    end
  end

  private

  def listing_scopes(kind, status)
    raise ArgumentError unless kind.blank? || KINDS.include?(kind)
    raise ArgumentError unless status.blank? || %w[open acknowledged all].include?(status)

    (kind.presence ? [kind] : KINDS).index_with { |type| filtered_scope(type, status.presence || 'open') }
  end

  def listing_rows(scopes, page)
    rows = scopes.flat_map do |type, scope|
      scope.reorder(updated_at: :desc, id: :desc).limit(page * PAGE_SIZE).map { |record| [type, record] }
    end
    rows.sort_by { |type, record| [-record.updated_at.to_f, type, -record.id] }
  end

  def parse_id(id)
    match = /\A(event|delivery|media|reservation)-([1-9]\d*)\z/.match(id.to_s)
    raise ActiveRecord::RecordNotFound unless match

    [match[1], match[2].to_i]
  end

  def scope(kind)
    case kind
    when 'event'
      WhatsappUnifiedEvent.where(whatsapp_inbox_link: @link).where(state: %w[pending review disabled])
    when 'media'
      WhatsappUnifiedMessage.where(whatsapp_inbox_link: @link, media_review_status: %w[pending review rejected])
    when 'reservation'
      WhatsappUnifiedMessage.where(whatsapp_inbox_link: @link, message_id: nil, state: 'review')
    when 'delivery'
      attributes = <<~SQL.squish
        (CASE WHEN json_typeof(messages.content_attributes) = 'string'
         THEN (messages.content_attributes #>> '{}')::json ELSE messages.content_attributes END)
      SQL
      Message.where(account_id: @link.account_id, inbox_id: @link.primary_inbox_id, private: false, message_type: :outgoing)
             .where("#{attributes}->'whatsapp_transport'->>'link_id' = ?", @link.id.to_s)
             .where("#{attributes}->'whatsapp_transport'->>'delivery_state' IN ('attempting', 'uncertain')")
    else
      raise ArgumentError
    end
  end

  def filtered_scope(kind, status)
    relation = scope(kind)
    return relation if status == 'all'

    table = relation.klass.table_name
    acknowledged = WhatsappUnifiedReviewAction.where(whatsapp_inbox_link: @link, subject_kind: kind, action: 'acknowledge')
                                              .where("subject_id = #{table}.id AND subject_updated_at = #{table}.updated_at")
    relation.where("#{status == 'open' ? 'NOT ' : ''}EXISTS (#{acknowledged.select('1').to_sql})")
  end

  def audit_scope(kind, record)
    WhatsappUnifiedReviewAction.where(whatsapp_inbox_link: @link, subject_kind: kind, subject_id: record.id)
  end

  def revision(kind, record)
    Digest::SHA256.hexdigest([@link.id, @link.enabled?, @link.activated_at&.iso8601(6), kind, record.id,
                              record.updated_at.iso8601(6), audit_scope(kind, record).maximum(:id)].join(':'))
  end

  def acknowledged_action(kind, record)
    audit_scope(kind, record).where(action: 'acknowledge', subject_updated_at: record.updated_at).order(id: :desc).first
  end

  def actions(kind, record)
    { recheck: current_generation?(kind, record) && retryable?(kind, record), acknowledge: acknowledged_action(kind, record).nil? }
  end

  def current_generation?(kind, record)
    return false unless @link.enabled? && @link.activated_at.present?
    return record.activation_cutoff == @link.activated_at if kind == 'event'
    return record.message.present? && record.message.created_at >= @link.activated_at if kind == 'media'

    true
  end

  def retryable?(kind, record)
    case kind
    when 'event' then %w[pending review].include?(record.state) && record.payload.present?
    when 'media' then record.message_id.present?
    else false
    end
  end

  def recheck(kind, record)
    if kind == 'event'
      record.update!(state: 'pending', attempts: 0, next_attempt_at: Time.current)
      Whatsapp::ProcessUnifiedEventJob.perform_later(record.id)
    else
      record.update!(media_review_status: 'pending')
      Whatsapp::ReconcileUnifiedMediaJob.perform_later(record.id)
    end
  end

  def serialize(kind, record)
    message = kind == 'delivery' ? record : record.try(:message)
    if kind == 'event'
      message = Whatsapp::UnifiedMessageIngestionService.message_for(record.whatsapp_message_identity) ||
                Whatsapp::UnifiedEventResolutionService.new(event: record).message ||
                Whatsapp::RetainedOutgoingEchoResolutionService.new(event: record).message
    end
    reviewed = acknowledged_action(kind, record)
    {
      id: "#{kind}-#{record.id}", kind: kind, state: state(kind, record), reason: reason(kind, record),
      created_at: record.created_at, updated_at: record.updated_at, attempts: record.try(:attempts),
      next_attempt_at: record.try(:next_attempt_at), reviewed_at: reviewed&.created_at, reviewed_by_id: reviewed&.actor_id,
      actions: actions(kind, record), version: revision(kind, record)
    }.merge(identity_fields(kind, record)).merge(message_fields(message))
  end

  def identity_fields(kind, record)
    if kind == 'event'
      identity = record.whatsapp_message_identity
      return { provider: identity.provider, original_id: identity.provider_message_id, public_id: identity.external_id }
    end
    transport = kind == 'delivery' ? record.content_attributes.fetch('whatsapp_transport') : {}
    message = kind == 'delivery' ? record : record.message
    { provider: transport['provider'], original_id: record.try(:original_id), public_id: message&.source_id }
  end

  def message_fields(message)
    { message_id: message&.id, conversation_id: message&.conversation_id, conversation_display_id: message&.conversation&.display_id }
  end

  def state(kind, record)
    return record.content_attributes.dig('whatsapp_transport', 'delivery_state') if kind == 'delivery'
    return record.state if kind == 'reservation'

    kind == 'event' ? record.state : record.media_review_status
  end

  def reason(kind, record)
    return 'delivery_confirmation_uncertain' if kind == 'delivery'
    return 'reservation_without_message' if kind == 'reservation'

    kind == 'event' ? record.reason : record.media_review_reason
  end
end
