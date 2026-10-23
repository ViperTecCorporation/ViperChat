class AddConversationToVoipExternalCalls < ActiveRecord::Migration[7.1]
  def change
    add_reference :voip_external_calls, :conversation, foreign_key: true
    add_reference :voip_external_calls, :call_message, foreign_key: { to_table: :messages }, index: { unique: true }
  end
end
