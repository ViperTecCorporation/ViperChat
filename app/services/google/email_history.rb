class Google::EmailHistory
  PERIODS = %w[none 7d 30d 3m 6m 12m].freeze
  KEY = 'email_history'.freeze

  def self.validate!(period)
    raise ArgumentError, 'Invalid history period (maximum 12 months)' unless PERIODS.include?(period)

    period
  end

  def self.start!(channel, period, new_channel: false)
    validate!(period)
    now = Time.current.utc
    from = case period
           when '7d' then now - 7.days
           when '30d' then now - 30.days
           when '3m', '6m', '12m' then now - period.to_i.months
           else now
           end
    channel.with_lock do
      config = channel.provider_config.to_h.deep_dup
      config['receive_since'] = now.iso8601 if new_channel
      config[KEY] = {
        'id' => SecureRandom.uuid, 'period' => period, 'since' => from.iso8601,
        'until' => now.iso8601, 'day' => now.to_date.iso8601, 'uid' => 0,
        'processed' => 0, 'status' => period == 'none' ? 'stopped' : 'running'
      }
      channel.update!(provider_config: config)
    end
  end

  def self.update!(channel, id, attributes)
    channel.with_lock do
      config = channel.provider_config.to_h.deep_dup
      current = config[KEY]
      next false unless current && current['id'] == id && current['status'] == 'running'

      config[KEY] = current.merge(attributes)
      channel.update!(provider_config: config)
      true
    end
  end
end
