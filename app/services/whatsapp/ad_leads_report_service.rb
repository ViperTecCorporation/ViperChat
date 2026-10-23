# Standalone acquisition report includes WhatsApp inboxes without a partner link.
class Whatsapp::AdLeadsReportService < Whatsapp::PartnerInboxReportService
  private

  def prepare_channels(_pairs)
    inboxes = @account.inboxes.where(channel_type: 'Channel::Whatsapp').includes(:channel).to_a
    @channels = inboxes.index_by(&:id).transform_values(&:channel)
    @phones = inboxes.index_by(&:id).transform_values { |inbox| Whatsapp::InboxLinkPhoneService.normalize(inbox.channel.phone_number) }
  end
end
