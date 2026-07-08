json.id resource.id
json.contact_id resource.contact_id
json.conversation_id resource.conversation_id
json.scheduled_at resource.scheduled_at.to_i
json.send_message resource.send_message
json.message_content resource.message_content
json.is_completed resource.is_completed
json.created_at resource.created_at.to_i

json.user do
  json.partial! 'api/v1/models/user', formats: [:json], resource: resource.user if resource.user
end
