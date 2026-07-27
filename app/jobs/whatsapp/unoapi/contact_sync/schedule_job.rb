class Whatsapp::Unoapi::ContactSync::ScheduleJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    channels = Channel::Whatsapp.where(provider: 'unoapi', contact_sync_enabled: true).where.not(contact_sync_status: 'paused')
    channels.order(:id).find_each.with_index do |channel, index|
      Whatsapp::Unoapi::ContactSync::ConnectionCheckJob.set(wait: index.minutes).perform_later(channel.id)
    end
  end
end
