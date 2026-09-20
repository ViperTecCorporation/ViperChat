# ACCOUNT_ID=1 bundle exec rails runner script/repair_inherited_group_avatars.rb
# Apply only reviewed database IDs, never display IDs:
# ACCOUNT_ID=1 APPLY_IDS=39258 BACKUP_PATH=/private/backup.jsonl bundle exec rails runner script/repair_inherited_group_avatars.rb
account_id = Integer(ENV.fetch('ACCOUNT_ID'))
apply_ids = ENV.fetch('APPLY_IDS', '').split(',').map { |id| Integer(id) }
scope = Conversation.where(account_id: account_id, group: true)
                    .where("additional_attributes->>'group_picture_id' ~ '@(lid|s[.]whatsapp[.]net|c[.]us)$'")
scope = scope.where(id: apply_ids) if apply_ids.any?
backup = File.open(ENV.fetch('BACKUP_PATH'), File::WRONLY | File::CREAT | File::EXCL, 0o600) if apply_ids.any?
results = []
begin
  ActiveRecord::Base.connection.execute("SET statement_timeout = '5s'")
  ActiveRecord::Base.connection.execute("SET lock_timeout = '1s'")
  scope.find_each do |conversation|
    contact = conversation.contact
    contact.with_lock do
      repair = Whatsapp::Unoapi::InheritedGroupAvatarRepair.new(conversation)
      next unless repair.perform

      if backup
        backup.puts({ contact: contact.attributes, attachment: contact.avatar_attachment.attributes,
                      blob: contact.avatar.blob.attributes, conversations: contact.conversations.map(&:attributes) }.to_json)
        backup.flush
        backup.fsync
        raise 'Eligibility changed during repair' unless repair.perform(apply: true)
      end
      results << { id: conversation.id, display_id: conversation.display_id, account_id: conversation.account_id,
                   inbox_id: conversation.inbox_id, contact_id: contact.id, applied: backup.present? }
    end
  end
  puts results.to_json
ensure
  backup&.close
end
