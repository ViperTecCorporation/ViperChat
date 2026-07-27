class Whatsapp::IncomingMessageUnoapiService < Whatsapp::IncomingMessageWhatsappCloudService
  private

  def download_attachment_file(attachment_payload)
    downloaded_file = super
    return if downloaded_file.blank?

    Whatsapp::Unoapi::AudioTranscoder.new(downloaded_file).perform
  end

  def processed_params
    @processed_params ||= super.presence || params
  end
end
