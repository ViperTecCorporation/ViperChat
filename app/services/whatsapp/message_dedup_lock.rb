# Atomic dedup lock for WhatsApp incoming messages.
#
# Meta can deliver the same webhook event multiple times. This lock uses
# Redis SET NX EX to ensure only one worker processes a given source_id.
class Whatsapp::MessageDedupLock
  class Busy < StandardError; end

  KEY_PREFIX = Redis::RedisKeys::MESSAGE_SOURCE_KEY
  # Processing lease, not a cache of completed messages. SQL is the durable record.
  DEFAULT_TTL = 5.minutes.to_i

  def initialize(source_id, ttl: DEFAULT_TTL)
    @key = format(KEY_PREFIX, id: source_id)
    @ttl = ttl
    @token = SecureRandom.uuid
  end

  # Returns true when the lock is acquired (caller should proceed).
  # Returns false when another worker already holds the lock.
  def acquire!
    ::Redis::Alfred.set(@key, @token, nx: true, ex: @ttl)
  end

  def release!
    ::Redis::Alfred.delete_if_equals(@key, @token)
  end

  def ensure_owned!
    raise Busy, 'WhatsApp message processing lease expired' unless ::Redis::Alfred.get(@key) == @token
  end
end
