class AddIndexAttachmentsOnMessageIdCreatedAt < ActiveRecord::Migration[7.0]
  def change
    add_index :attachments, [:message_id, :created_at],
              order: { created_at: :desc },
              name: 'index_attachments_on_message_id_and_created_at_desc'
  end
end
