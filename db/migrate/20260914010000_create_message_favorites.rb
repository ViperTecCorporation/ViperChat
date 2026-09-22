class CreateMessageFavorites < ActiveRecord::Migration[7.1]
  def change
    create_table :message_favorites do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :message, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end
    add_index :message_favorites, [:user_id, :message_id], unique: true
    add_index :message_favorites, [:account_id, :user_id, :id]
  end
end
