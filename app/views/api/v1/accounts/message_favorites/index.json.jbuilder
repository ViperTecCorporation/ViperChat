json.has_more @has_more
json.payload @favorites do |favorite|
  message = favorite.message
  json.id favorite.id
  json.contact_name message.conversation.group_title.presence || message.conversation.contact.name
  json.thumbnail message.conversation.group? ? message.conversation.group_avatar_url : message.conversation.contact.avatar_url
  json.inbox_name message.conversation.inbox.name
  json.message do
    json.partial! 'api/v1/models/message', message: message
  end
end
