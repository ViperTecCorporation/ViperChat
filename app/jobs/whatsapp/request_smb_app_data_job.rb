class Whatsapp::RequestSmbAppDataJob < ApplicationJob
  queue_as :low
  # Only pre-dispatch work may be retried. POST failures are journaled and never raised here.
  retry_on Whatsapp::ManagementApiClient::Error, Whatsapp::SmbAppDataService::PreparationError, wait: 5.minutes, attempts: 5

  def perform(channel_id)
    channel = Channel::Whatsapp.find_by(id: channel_id, provider: 'whatsapp_cloud')
    Whatsapp::SmbAppDataService.new(channel: channel).perform if channel
  end
end
