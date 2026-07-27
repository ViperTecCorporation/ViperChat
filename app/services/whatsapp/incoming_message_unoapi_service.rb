class Whatsapp::IncomingMessageUnoapiService < Whatsapp::IncomingMessageWhatsappCloudService
  private

  def processed_params
    @processed_params ||= super.presence || params
  end
end
