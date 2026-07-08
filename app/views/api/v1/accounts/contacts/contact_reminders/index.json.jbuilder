json.array! @contact_reminders do |contact_reminder|
  json.partial! 'api/v1/models/contact_reminder', formats: [:json], resource: contact_reminder
end
