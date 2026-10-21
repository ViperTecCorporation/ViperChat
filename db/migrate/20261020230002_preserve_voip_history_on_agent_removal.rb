class PreserveVoipHistoryOnAgentRemoval < ActiveRecord::Migration[7.1]
  def up
    add_column :voip_calls, :local_agent_id, :bigint
    execute <<~SQL.squish
      UPDATE voip_calls SET local_agent_id = account_users.user_id
      FROM voip_agent_extensions JOIN account_users ON account_users.id = voip_agent_extensions.account_user_id
      WHERE voip_calls.voip_agent_extension_id = voip_agent_extensions.id
    SQL
    change_column_null :voip_calls, :local_agent_id, false
    change_column_null :voip_agent_extensions, :account_user_id, true
    remove_foreign_key :voip_agent_extensions, :account_users
    add_foreign_key :voip_agent_extensions, :account_users, on_delete: :nullify
    remove_index :voip_agent_extensions, name: 'uniq_voip_extension_per_service'
    add_index :voip_agent_extensions, [:voip_service_id, :extension], unique: true,
                                                                      where: 'account_user_id IS NOT NULL', name: 'uniq_voip_extension_per_service'
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Removed agents have preserved VoIP history; ownership cannot be fabricated'
  end
end
