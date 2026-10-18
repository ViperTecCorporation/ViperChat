# Internal constructor context, never a visitor/provider-controlled payload flag.
module Whatsapp::HistoryIngestionSupport
  private

  def legacy_ingestion
    yield(nil) unless @historical && link
  end

  def eligible_timestamp?
    @historical || Time.zone.at(@event[:timestamp].to_i) >= link.activated_at ||
      WhatsappUnifiedMessage.exists?(whatsapp_inbox_link: link, original_id: @identity&.provider_message_id)
  end

  def adopt_history_counterpart
    return unless @historical && record.message_id.nil?

    Whatsapp::HistoricalCounterpartService.new(inbox: @inbox, identity: @identity, record: record).perform
  end
end
