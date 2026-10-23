# Attribution evidence and estimated windows, not a statement of Meta billing.
class Whatsapp::AdLeadWindowTracker
  def initialize(window:)
    @window = window
    @pending = {}
    @active = {}
    @entries = []
  end

  def receive(row, key)
    entry = row.slice(:contact_id, :business_phone, :inbox_id, :provider, :received_providers, :ad_source_id, :has_click_id)
               .merge(message_id: row[:id], received_at: row[:created_at], free_meta_messages: 0)
    @entries << entry
    @pending[key] = entry
  end

  def open(key, time, message_id)
    entry = @pending[key]
    return unless entry && time >= entry[:received_at] && time - entry[:received_at] <= 24.hours

    entry.merge!(window_start: time, window_end: time + @window, window_days: @window / 1.day, response_message_id: message_id)
    @active[key] = entry
    @pending.delete(key)
  end

  def free?(key, time)
    @active[key] && time < @active[key][:window_end]
  end

  def count(key)
    @active.fetch(key)[:free_meta_messages] += 1
  end

  def entries(since:, until_time:)
    cutoff = [until_time, Time.current].min
    @entries.filter_map do |entry|
      next unless entry[:received_at] >= since && entry[:received_at] < until_time

      elapsed = entry[:window_start] ? [[cutoff - entry[:window_start], 0].max / 1.day, entry[:window_days]].min.round(2) : 0
      entry.merge(state: window_state(entry, cutoff), exempt_days_elapsed: elapsed)
    end
  end

  private

  def window_state(entry, cutoff)
    return cutoff < entry[:window_end] ? 'active' : 'expired' if entry[:window_start]

    cutoff < entry[:received_at] + 24.hours ? 'awaiting_response' : 'no_eligible_response'
  end
end
