json.id resource.id
json.avatar_url resource.try(:avatar_url)
json.channel_id resource.channel_id
json.name resource.name
operational_link = Whatsapp::OperationalInboxService.metadata(inbox: resource) if resource.whatsapp?
json.whatsapp_inbox_link operational_link if operational_link
json.channel_type resource.channel_type
json.provider resource.channel.try(:provider)
