FactoryBot.define do
  factory :scheduled_message do
    account
    scheduled_at { 1.hour.from_now }
    status { :scheduled }
    reason { nil }
    content { 'Scheduled message' }
    content_type { 'text' }
    content_attributes { {} }
    attachment_blob_ids { [] }

    after(:build) do |scheduled_message|
      scheduled_message.account = create(:account) unless scheduled_message.account&.persisted?
      channel = create(
        :channel_whatsapp,
        account: scheduled_message.account,
        provider: 'unoapi',
        sync_templates: false,
        validate_provider_config: false
      )
      scheduled_message.inbox ||= channel.inbox
      scheduled_message.contact ||= create(:contact, account: scheduled_message.account)
      contact_inbox = create(:contact_inbox, contact: scheduled_message.contact, inbox: scheduled_message.inbox)
      scheduled_message.conversation ||= create(
        :conversation,
        account: scheduled_message.account,
        inbox: scheduled_message.inbox,
        contact: scheduled_message.contact,
        contact_inbox: contact_inbox
      )
      scheduled_message.label ||= create(:label, account: scheduled_message.account)
      scheduled_message.created_by ||= create(:user, account: scheduled_message.account)
      scheduled_message.sender ||= scheduled_message.created_by
      unless scheduled_message.inbox.members.exists?(scheduled_message.sender.id)
        create(:inbox_member, inbox: scheduled_message.inbox, user: scheduled_message.sender)
      end
    end

    after(:build) do |scheduled_message|
      next if scheduled_message.items.any?

      scheduled_message.items.build(position: 0, content: scheduled_message.content, content_type: 'text')
    end
  end

  factory :scheduled_message_item do
    scheduled_message
    sequence(:position) { |number| number % ScheduledMessage::MAX_ITEMS }
    content { 'Sequence item' }
    content_type { 'text' }
    content_attributes { {} }
    attachment_blob_ids { [] }
    status { :pending }
    voice_message { false }
  end
end
