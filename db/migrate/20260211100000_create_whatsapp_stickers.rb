class CreateWhatsappStickers < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_stickers do |t|
      t.bigint :account_id, null: false
      t.bigint :inbox_id, null: false
      t.bigint :blob_id, null: false
      t.datetime :last_used_at

      t.timestamps
    end

    add_index :whatsapp_stickers, :account_id
    add_index :whatsapp_stickers, :inbox_id
    add_index :whatsapp_stickers, [:inbox_id, :last_used_at]
    add_index :whatsapp_stickers, [:inbox_id, :blob_id], unique: true
    add_index :whatsapp_stickers, :blob_id
  end
end
