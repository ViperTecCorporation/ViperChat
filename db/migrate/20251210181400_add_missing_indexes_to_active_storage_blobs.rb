class AddMissingIndexesToActiveStorageBlobs < ActiveRecord::Migration[7.0]
  def change
    add_index :active_storage_blobs, :key,
              name: 'idx_blobs_key',
              if_not_exists: true

    add_index :active_storage_blobs, :created_at,
              name: 'idx_blobs_created_at',
              if_not_exists: true

    add_index :active_storage_blobs, :checksum,
              name: 'idx_blobs_checksum',
              if_not_exists: true
  end
end
