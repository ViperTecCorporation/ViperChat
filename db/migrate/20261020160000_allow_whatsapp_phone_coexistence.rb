class AllowWhatsappPhoneCoexistence < ActiveRecord::Migration[7.1]
  def up
    add_index :channel_whatsapp, :phone_number, unique: true, where: "provider = 'unoapi'", name: 'index_channel_whatsapp_unoapi_phone'
    add_index :channel_whatsapp, :phone_number, unique: true, where: "provider IS DISTINCT FROM 'unoapi'",
                                                name: 'index_channel_whatsapp_official_phone'
    remove_index :channel_whatsapp, name: 'index_channel_whatsapp_on_phone_number'
  end

  def down
    # Recreating the original constraint must succeed before either replacement is removed.
    # PostgreSQL refuses rollback if a coexistence pair exists; never delete data to force it.
    add_index :channel_whatsapp, :phone_number, unique: true, name: 'index_channel_whatsapp_on_phone_number'
    remove_index :channel_whatsapp, name: 'index_channel_whatsapp_unoapi_phone'
    remove_index :channel_whatsapp, name: 'index_channel_whatsapp_official_phone'
  end
end
