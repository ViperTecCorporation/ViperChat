class MakeLabelOptionalInScheduledMessages < ActiveRecord::Migration[7.1]
  def change
    change_column_null :scheduled_messages, :label_id, true
  end
end
