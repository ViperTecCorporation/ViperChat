class Conversations::PinService
  LIMIT = 3
  KEY = 'pinned_conversations'.freeze

  def initialize(user, account)
    @user = user
    @account = account
  end

  def ids
    Array(@user.ui_settings&.dig(KEY, @account.id.to_s)).map(&:to_i).select(&:positive?).uniq.first(LIMIT)
  end

  def update(conversation, pinned)
    @user.with_lock do
      pins = ids
      pins &= @account.conversations.where(display_id: pins).pluck(:display_id)
      pins.delete(conversation.display_id)
      if pinned
        raise ArgumentError, 'pin_limit_reached' if pins.size >= LIMIT

        pins.unshift(conversation.display_id)
      end
      settings = @user.ui_settings || {}
      @user.update!(ui_settings: settings.merge(KEY => (settings[KEY] || {}).merge(@account.id.to_s => pins)))
      pins
    end
  end

  # Sort only the already authorized/filtered relation, before pagination.
  def order(scope)
    pins = ids
    return scope if pins.empty?

    cases = pins.each_with_index.map { |id, index| "WHEN #{id} THEN #{index}" }.join(' ')
    rank = "CASE conversations.display_id #{cases} ELSE #{LIMIT} END"
    if scope.select_values.empty?
      columns = if scope.distinct_value
                  Conversation.connection.columns_for_distinct('conversations.*', scope.order_values)
                else
                  'conversations.*'
                end
      scope = scope.select(Arel.sql(columns))
    end
    scope.select(Arel.sql("#{rank} AS conversation_pin_rank")).reorder(Arel.sql("#{rank} ASC"), *scope.order_values)
  end
end
