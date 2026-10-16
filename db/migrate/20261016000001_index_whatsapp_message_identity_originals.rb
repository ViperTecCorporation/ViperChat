class IndexWhatsappMessageIdentityOriginals < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :whatsapp_message_identities, [:account_id, :inbox_id, :provider_message_id],
              where: 'provider_message_id IS NOT NULL', name: 'idx_wa_identity_original', algorithm: :concurrently
  end
end
