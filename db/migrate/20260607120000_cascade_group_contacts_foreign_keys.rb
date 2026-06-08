class CascadeGroupContactsForeignKeys < ActiveRecord::Migration[7.0]
  def up
    remove_foreign_key :group_contacts, :accounts
    remove_foreign_key :group_contacts, :contacts
    remove_foreign_key :group_contacts, :conversations

    add_foreign_key :group_contacts, :accounts, on_delete: :cascade
    add_foreign_key :group_contacts, :contacts, on_delete: :cascade
    add_foreign_key :group_contacts, :conversations, on_delete: :cascade
  end

  def down
    remove_foreign_key :group_contacts, :accounts
    remove_foreign_key :group_contacts, :contacts
    remove_foreign_key :group_contacts, :conversations

    add_foreign_key :group_contacts, :accounts
    add_foreign_key :group_contacts, :contacts
    add_foreign_key :group_contacts, :conversations
  end
end
