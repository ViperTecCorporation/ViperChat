class CreateVoipProviderEvents < ActiveRecord::Migration[7.1]
  def change
    create_external_calls
    create_events
    add_reference :voip_calls, :voip_external_call, foreign_key: true
    add_column :voip_calls, :provider_participant_id, :string
    add_index :voip_calls, [:voip_external_call_id, :provider_participant_id, :voip_agent_extension_id], unique: true,
                                                                                                         name: 'voip_provider_participation'
  end

  def create_external_calls
    create_table :voip_external_calls do |t|
      t.references :voip_service, null: false, foreign_key: true
      t.string :source_instance_id, null: false, limit: 200
      t.string :provider_call_id, null: false, limit: 200
      t.bigint :revision, null: false, default: 0
      t.jsonb :snapshot, null: false, default: {}
      t.timestamps
    end
    add_index :voip_external_calls, [:voip_service_id, :source_instance_id, :provider_call_id], unique: true, name: 'voip_external_call_identity'
  end

  def create_events
    create_table :voip_provider_events do |t|
      t.references :voip_service, null: false, foreign_key: true
      t.string :source_instance_id, null: false, limit: 200
      t.string :event_id, null: false, limit: 200
      t.string :provider_call_id, null: false, limit: 200
      t.bigint :revision, null: false
      t.string :content_digest, null: false
      t.jsonb :payload, null: false
      t.datetime :processed_at
      t.timestamps
    end
    add_index :voip_provider_events, [:voip_service_id, :source_instance_id, :event_id], unique: true, name: 'voip_provider_event_identity'
    add_index :voip_provider_events, [:voip_service_id, :source_instance_id, :provider_call_id, :revision], unique: true,
                                                                                                            name: 'voip_provider_event_revision'
    add_index :voip_provider_events, :created_at, where: 'processed_at IS NULL', name: 'voip_pending_provider_events'
  end
end
