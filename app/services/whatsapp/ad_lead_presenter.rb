class Whatsapp::AdLeadPresenter
  def initialize(account:)
    @account = account
  end

  def perform(entries)
    contacts = @account.contacts.where(id: entries.map { |entry| entry[:contact_id] }).pluck(:id, :name, :phone_number)
                       .to_h { |id, name, phone| [id, { contact_name: name, contact_phone: phone }] }
    inboxes = @account.inboxes.where(id: entries.pluck(:inbox_id)).pluck(:id, :name).to_h
    entries.map { |entry| entry.merge(contacts.fetch(entry[:contact_id], {})).merge(inbox_name: inboxes[entry[:inbox_id]]) }
  end
end
