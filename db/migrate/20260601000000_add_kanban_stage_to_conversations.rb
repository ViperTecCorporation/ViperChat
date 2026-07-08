class AddKanbanStageToConversations < ActiveRecord::Migration[7.0]
  def change
    add_column :conversations, :kanban_stage, :string
    add_index :conversations, :kanban_stage
  end
end
