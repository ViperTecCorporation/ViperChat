# Network lookup only: no message send, remote contact import, merge or history move.
ActiveRecord::Base.logger = nil
contact = Contact.find_by!(id: 231, account_id: 1, phone_number: '+5566996803524')
channel = Inbox.find_by!(id: 1, account_id: 1).channel
verification = Whatsapp::Unoapi::ContactSync::Client.new(channel).verify_contact('5566996803524').with_indifferent_access
lid = verification[:user_id].to_s
raise 'Network did not confirm the new number' unless verification[:status] == 'valid' && verification[:wa_id] == '5566996803524'
raise 'Network returned an invalid or cancelled LID' unless lid.match?(/\A\d+@lid\z/) && lid != '242309471989955@lid'

Contact.transaction do
  contact.lock!
  raise 'Contact changed after maintenance' unless contact.phone_number == '+5566996803524' && contact.bsuid.nil?
  raise 'New LID already belongs to another contact' if contact.account.contacts.where(bsuid: lid).where.not(id: contact.id).exists?

  owners = ContactInbox.joins(:inbox).where(inboxes: { account_id: 1 }, source_id: lid)
  raise 'New LID alias belongs to another contact' if owners.where.not(contact_id: contact.id).exists?

  previous = contact.contact_inboxes.order(:id).pluck(:id, :source_id, :inbox_id)
  link = channel.inbox.contact_inboxes.create_or_find_by!(source_id: lid) { |row| row.contact = contact }
  raise 'New alias is not active for this contact' unless link.contact_id == contact.id && !link.whatsapp_identity_retired?

  contact.update!(bsuid: lid)
  raise 'A historical alias was modified' unless contact.contact_inboxes.where(id: previous.pluck(0)).order(:id).pluck(:id, :source_id,
                                                                                                                       :inbox_id) == previous

  result = { contact_id: contact.id, phone: contact.phone_number, user_id: contact.bsuid,
             new_alias_id: link.id, historical_aliases_preserved: previous.size }
  puts "NEW_IDENTITY_VERIFIED=#{result.to_json}"
end
