class AddMissingIndexesToConversationParticipants < ActiveRecord::Migration[7.0]
  def change
    add_index :conversation_participants, :conversation_id,
              name: 'idx_conv_part_conversation_id',
              if_not_exists: true

    add_index :conversation_participants, :user_id,
              name: 'idx_conv_part_user_id',
              if_not_exists: true
  end
end
