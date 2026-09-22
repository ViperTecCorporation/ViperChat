# Dry-run: ACCOUNT_ID=1 bundle exec rails runner script/repair_duplicate_group_avatars.rb
# Apply reviewed contact IDs only, with a new private backup file:
# ACCOUNT_ID=1 APPLY_CONTACT_IDS=4697,51828 BACKUP_PATH=/private/group-avatar.jsonl bundle exec rails runner script/repair_duplicate_group_avatars.rb
account_id = Integer(ENV.fetch('ACCOUNT_ID'))
apply_ids = ENV.fetch('APPLY_CONTACT_IDS', '').split(',').map { |id| Integer(id) }
scope = Contact.where(account_id: account_id).where(id: ContactInbox.where("source_id LIKE '%@g.us'").select(:contact_id))
scope = scope.where(id: apply_ids) if apply_ids.any?
raise 'Contact IDs do not belong to this account/group scope' if apply_ids.any? && scope.count != apply_ids.uniq.size

backup = File.open(ENV.fetch('BACKUP_PATH'), File::WRONLY | File::CREAT | File::EXCL, 0o600) if apply_ids.any?
begin
  ActiveRecord::Base.connection.execute("SET statement_timeout = '5s'")
  ActiveRecord::Base.connection.execute("SET lock_timeout = '1s'")
  scope.find_each do |contact|
    service = Avatar::GroupAvatarService.new(contact)
    result = backup ? service.repair!(backup: backup) : service.plan
    next if result[:status] == 'no_duplicates'

    puts result.merge(contact_id: contact.id, account_id: account_id).to_json
  end
ensure
  backup&.close
end
