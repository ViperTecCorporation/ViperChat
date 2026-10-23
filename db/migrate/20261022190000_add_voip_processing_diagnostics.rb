class AddVoipProcessingDiagnostics < ActiveRecord::Migration[7.1]
  def change
    [:voip_provider_events, :voip_call_artifacts].each do |table|
      change_table table, bulk: true do |t|
        if table == :voip_provider_events
          t.integer :attempts, null: false, default: 0
          t.datetime :next_attempt_at
        end
        t.string :last_error_code
        t.datetime :last_reprocessed_at
        t.bigint :last_reprocessed_by_id
      end
    end
  end
end
