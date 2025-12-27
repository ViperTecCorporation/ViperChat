json.payload do
  json.array! @inbox_members do |inbox_member|
    agent = inbox_member.user
    json.partial! 'api/v1/models/agent', formats: [:json], resource: agent
    json.inbox_member do
      json.id inbox_member.id
      json.webrtc_username inbox_member.webrtc_username
      json.has_webrtc_jwt inbox_member.webrtc_jwt.present?
    end
  end
end
