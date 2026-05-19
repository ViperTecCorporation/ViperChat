json.meta do
  json.mine_count @conversations_count[:mine_count]
  json.assigned_count @conversations_count[:assigned_count]
  json.unassigned_count @conversations_count[:unassigned_count]
  json.waiting_count @conversations_count[:waiting_count]
  json.group_count @conversations_count[:group_count]
  json.all_count @conversations_count[:all_count]
  json.internal_count @conversations_count[:internal_count]
end
