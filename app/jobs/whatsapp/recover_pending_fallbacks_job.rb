# Only a not-yet-claimed alternate provider may be recovered. Never replay an
# attempting/uncertain request, even after a worker crash.
class Whatsapp::RecoverPendingFallbacksJob < ApplicationJob
  queue_as :low

  # Message uses store(coder: JSON); existing rows can be a JSON string or object.
  ATTRIBUTES_SQL = "(CASE WHEN jsonb_typeof(content_attributes::jsonb) = 'string' " \
                   "THEN (content_attributes #>> '{}')::jsonb ELSE content_attributes::jsonb END)".freeze
  TRANSPORT_SQL = "#{ATTRIBUTES_SQL}->'whatsapp_transport'".freeze

  def perform
    scope = Message.outgoing.where(private: false, status: [:progress, :failed])
    pending = scope.where("#{TRANSPORT_SQL}->>'fallback_pending' = 'true'")
                   .where("#{TRANSPORT_SQL}->>'delivery_attempt_id' IS NULL")
    rejected = scope.where("#{TRANSPORT_SQL}->>'delivery_state' = 'failed'")
                    .where("#{TRANSPORT_SQL}->>'fallback_from' IS NULL")
    pending.or(rejected)
           .where('updated_at < ?', 30.seconds.ago).order(:id).limit(100).each do |message|
      Whatsapp::UnifiedDeliveryStateService.new(message: message).prepare_fallback
    end
  end
end
