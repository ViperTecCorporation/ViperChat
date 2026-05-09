class MergeUnoapiContactDuplicates < ActiveRecord::Migration[7.1]
  class MigrationInbox < ApplicationRecord
    self.table_name = 'inboxes'
  end

  class MigrationContactInbox < ApplicationRecord
    self.table_name = 'contact_inboxes'
  end

  class MigrationContact < ApplicationRecord
    self.table_name = 'contacts'
  end

  class MigrationConversation < ApplicationRecord
    self.table_name = 'conversations'
  end

  class MigrationMessage < ApplicationRecord
    self.table_name = 'messages'
  end

  def up
    unoapi_inbox_ids.each do |inbox_id|
      merge_inbox_duplicate_phone_contacts(inbox_id)
      merge_inbox_contact_alias_conversations(inbox_id)
    end
  end

  def down
    # no-op: this data migration merges duplicate historical conversations.
  end

  private

  def unoapi_inbox_ids
    MigrationInbox.joins(
      "INNER JOIN channel_whatsapp ON channel_whatsapp.id = inboxes.channel_id AND inboxes.channel_type = 'Channel::Whatsapp'"
    ).where(channel_whatsapp: { provider: 'unoapi' }).pluck(:id)
  end

  def merge_inbox_contact_alias_conversations(inbox_id)
    MigrationContactInbox.where(inbox_id: inbox_id)
                         .where("source_id LIKE '%@lid'")
                         .find_each do |lid_contact_inbox|
      merge_contact_conversations(lid_contact_inbox)
    end
  end

  def merge_inbox_duplicate_phone_contacts(inbox_id)
    duplicate_phone_numbers(inbox_id).each do |phone_number|
      contact_ids = contact_ids_for_phone(inbox_id, phone_number)
      merge_duplicate_contacts(inbox_id, contact_ids)
    end
  end

  def duplicate_phone_numbers(inbox_id)
    MigrationContact.joins('INNER JOIN contact_inboxes ON contact_inboxes.contact_id = contacts.id')
                    .where(contact_inboxes: { inbox_id: inbox_id })
                    .where.not(phone_number: [nil, ''])
                    .group(:phone_number)
                    .having('COUNT(DISTINCT contacts.id) > 1')
                    .pluck(:phone_number)
  end

  def contact_ids_for_phone(inbox_id, phone_number)
    MigrationContact.joins('INNER JOIN contact_inboxes ON contact_inboxes.contact_id = contacts.id')
                    .where(contact_inboxes: { inbox_id: inbox_id })
                    .where(phone_number: phone_number)
                    .distinct
                    .pluck(:id)
  end

  def merge_duplicate_contacts(inbox_id, contact_ids)
    contacts = MigrationContact.where(id: contact_ids).to_a
    return if contacts.size <= 1

    target = preferred_contact(inbox_id, contacts)
    (contacts - [target]).each do |mergee|
      merge_contacts(target, mergee)
    end
    merge_target_contact_conversations(inbox_id, target.id)
  end

  def merge_contacts(target, mergee)
    ContactMergeAction.new(
      account: Account.find(target.account_id),
      base_contact: Contact.find(target.id),
      mergee_contact: Contact.find(mergee.id)
    ).perform
  end

  def preferred_contact(inbox_id, contacts)
    contacts.max_by do |contact|
      [
        last_contact_conversation_at(inbox_id, contact.id) || Time.zone.at(0),
        contact.updated_at || Time.zone.at(0),
        contact.id
      ]
    end
  end

  def last_contact_conversation_at(inbox_id, contact_id)
    MigrationConversation.where(inbox_id: inbox_id, contact_id: contact_id, group: false).maximum(:last_activity_at)
  end

  def merge_target_contact_conversations(inbox_id, contact_id)
    contact_inbox_ids = MigrationContactInbox.where(inbox_id: inbox_id, contact_id: contact_id).select(:id)
    conversations = MigrationConversation.where(
      inbox_id: inbox_id,
      contact_id: contact_id,
      contact_inbox_id: contact_inbox_ids,
      group: false
    ).to_a

    merge_conversations(conversations)
  end

  def merge_contact_conversations(lid_contact_inbox)
    conversations = MigrationConversation.where(
      inbox_id: lid_contact_inbox.inbox_id,
      contact_id: lid_contact_inbox.contact_id,
      contact_inbox_id: contact_alias_ids(lid_contact_inbox)
    ).where(group: false).to_a

    merge_conversations(conversations)
  end

  def merge_conversations(conversations)
    return if conversations.size <= 1

    target = preferred_conversation(conversations)
    mergees = conversations - [target]

    MigrationMessage.where(conversation_id: mergees.map(&:id)).update_all(conversation_id: target.id) # rubocop:disable Rails/SkipsModelValidations
    target.update_columns(merged_conversation_attributes(conversations)) # rubocop:disable Rails/SkipsModelValidations
    Conversation.where(id: mergees.map(&:id)).find_each(&:destroy!)
  end

  def merged_conversation_attributes(conversations)
    {
      last_activity_at: conversations.filter_map(&:last_activity_at).max,
      updated_at: Time.current
    }
  end

  def contact_alias_ids(contact_inbox)
    MigrationContactInbox.where(
      inbox_id: contact_inbox.inbox_id,
      contact_id: contact_inbox.contact_id
    ).select(:id)
  end

  def preferred_conversation(conversations)
    conversations.select { |conversation| conversation_source_id(conversation).exclude?('@') }
                 .max_by { |conversation| [conversation.last_activity_at, conversation.id] } ||
      conversations.max_by { |conversation| [conversation.last_activity_at, conversation.id] }
  end

  def conversation_source_id(conversation)
    MigrationContactInbox.find(conversation.contact_inbox_id).source_id.to_s
  end
end
