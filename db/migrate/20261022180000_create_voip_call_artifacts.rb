class CreateVoipCallArtifacts < ActiveRecord::Migration[7.1]
  def change
    create_table :voip_call_artifacts do |t|
      t.references :voip_external_call, null: false, foreign_key: true, index: { unique: true }
      t.references :message, foreign_key: true
      t.references :conversation, foreign_key: true
      t.bigint :desired_revision, null: false, default: 0
      t.bigint :applied_revision, null: false, default: 0
      t.jsonb :snapshot, null: false, default: {}
      t.string :state, null: false, default: 'pending'
      t.string :recording_digest
      t.integer :attempts, null: false, default: 0
      t.datetime :next_attempt_at
      t.timestamps
    end
    add_index :voip_call_artifacts, [:state, :next_attempt_at]
  end
end
