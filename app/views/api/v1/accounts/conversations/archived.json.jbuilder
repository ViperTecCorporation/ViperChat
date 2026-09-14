json.has_more @conversations.next_page.present?
json.count @conversations.total_count
json.payload do
  json.array! @conversations do |conversation|
    json.partial! 'api/v1/conversations/partials/conversation', conversation: conversation
  end
end
