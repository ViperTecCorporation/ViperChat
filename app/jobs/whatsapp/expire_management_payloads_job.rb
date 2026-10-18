# Keep receipt digests for idempotency. Expiry applies to raw webhook bodies,
# never customer messages, attachments or imported history.
class Whatsapp::ExpireManagementPayloadsJob < ApplicationJob
  queue_as :housekeeping

  def perform
    WhatsappManagementEvent.expired.where.not(payload: {}).find_each do |event|
      event.with_lock do
        next if event.expires_at > Time.current || event.payload.blank?

        updates = { payload: {} }
        if event.state == 'pending_import'
          updates[:state] = 'review'
          updates[:reason] = 'payload_expired'
        end
        event.update!(updates)
      end
    end
  end
end
