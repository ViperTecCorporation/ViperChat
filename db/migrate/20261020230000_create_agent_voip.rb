class CreateAgentVoip < ActiveRecord::Migration[7.1]
  def change
    create_services
    create_bindings
    create_calls
    create_observations
    create_favorites
  end

  private

  def create_services
    create_table :voip_services do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :wss_url, null: false
      t.string :sip_domain, null: false
      t.boolean :enabled, null: false, default: true
      t.boolean :allow_self_configuration, null: false, default: true
      t.boolean :transfer_enabled, null: false, default: false
      t.integer :registration_expires, null: false, default: 300
      t.jsonb :allowed_user_ids, null: false, default: []
      t.text :encrypted_credentials
      t.timestamps
    end
  end

  def create_bindings
    create_table :voip_agent_extensions do |t|
      t.references :account_user, null: false, foreign_key: true
      t.references :voip_service, null: false, foreign_key: true
      t.string :extension, null: false
      t.string :auth_username, null: false
      t.text :encrypted_credentials
      t.boolean :active, null: false, default: false
      t.timestamps
    end
    add_index :voip_agent_extensions, [:account_user_id, :voip_service_id], unique: true, name: 'uniq_voip_binding_per_service'
    add_index :voip_agent_extensions, [:voip_service_id, :extension], unique: true, name: 'uniq_voip_extension_per_service'
    add_index :voip_agent_extensions, :account_user_id, unique: true, where: 'active = true', name: 'uniq_active_voip_binding'
  end

  def create_calls
    create_table :voip_calls do |t|
      t.references :account, null: false, foreign_key: true
      t.references :voip_agent_extension, null: false, foreign_key: true
      t.string :client_call_id, null: false
      t.string :sip_call_id
      t.string :direction, null: false
      t.string :remote_address, null: false
      t.string :remote_name
      t.string :state, null: false, default: 'initiating'
      t.string :origin, null: false, default: 'client_observed'
      call_time_fields(t)
      t.timestamps
    end
    add_index :voip_calls, [:voip_agent_extension_id, :client_call_id], unique: true, name: 'uniq_voip_client_call'
    add_index :voip_calls, [:account_id, :started_at]
  end

  def call_time_fields(table)
    table.integer :last_sequence, null: false, default: 0
    table.integer :sip_code
    table.string :end_reason
    table.datetime :started_at, null: false
    table.datetime :answered_at
    table.datetime :ended_at
    table.datetime :last_observed_at, null: false
  end

  def create_observations
    create_table :voip_call_observations do |t|
      t.references :voip_call, null: false, foreign_key: true
      t.string :event_id, null: false
      t.integer :sequence, null: false
      t.string :state, null: false
      t.jsonb :details, null: false, default: {}
      t.timestamps
    end
    add_index :voip_call_observations, [:voip_call_id, :event_id], unique: true, name: 'uniq_voip_observation'
    add_index :voip_call_observations, [:voip_call_id, :sequence], unique: true, name: 'uniq_voip_observation_sequence'
  end

  def create_favorites
    create_table :voip_favorites do |t|
      t.references :account_user, null: false, foreign_key: true
      t.references :voip_service, null: false, foreign_key: true
      t.string :name, null: false
      t.string :address, null: false
      t.timestamps
    end
    add_index :voip_favorites, [:account_user_id, :voip_service_id, :address], unique: true, name: 'uniq_voip_favorite'
  end
end
