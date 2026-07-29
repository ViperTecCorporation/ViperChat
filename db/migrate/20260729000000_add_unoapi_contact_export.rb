class AddUnoapiContactExport < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_whatsapp, :contact_export_enabled, :boolean, default: false, null: false
  end
end
