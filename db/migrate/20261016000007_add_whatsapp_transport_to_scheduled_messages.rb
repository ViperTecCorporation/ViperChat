class AddWhatsappTransportToScheduledMessages < ActiveRecord::Migration[7.1]
  def change
    add_column :scheduled_messages, :whatsapp_transport, :jsonb, default: {}, null: false
    add_column :scheduled_message_items, :whatsapp_transport, :jsonb, default: {}, null: false
  end
end
