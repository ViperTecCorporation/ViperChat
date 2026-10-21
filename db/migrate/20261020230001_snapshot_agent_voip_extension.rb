class SnapshotAgentVoipExtension < ActiveRecord::Migration[7.1]
  def up
    add_column :voip_calls, :local_extension, :string
    execute <<~SQL.squish
      UPDATE voip_calls SET local_extension = voip_agent_extensions.extension
      FROM voip_agent_extensions WHERE voip_calls.voip_agent_extension_id = voip_agent_extensions.id
    SQL
    change_column_null :voip_calls, :local_extension, false
  end

  def down
    remove_column :voip_calls, :local_extension
  end
end
