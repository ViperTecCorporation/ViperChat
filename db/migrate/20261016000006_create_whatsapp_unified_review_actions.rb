class CreateWhatsappUnifiedReviewActions < ActiveRecord::Migration[7.1]
  def change
    change_table :whatsapp_unified_messages, bulk: true do |t|
      t.string :media_review_status
      t.string :media_review_reason
    end

    create_table :whatsapp_unified_review_actions do |t|
      t.references :whatsapp_inbox_link, null: false, foreign_key: { on_delete: :cascade }
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :subject_kind, null: false
      t.bigint :subject_id, null: false
      t.datetime :subject_updated_at, null: false, precision: 6
      t.string :action, null: false
      t.timestamps
    end
    add_index :whatsapp_unified_review_actions, [:whatsapp_inbox_link_id, :subject_kind, :subject_id, :id], name: 'idx_wa_review_subject'
  end
end
