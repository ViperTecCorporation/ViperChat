class ChangeCaptainDocumentExternalLinkToText < ActiveRecord::Migration[7.0]
  OLD_INDEX_NAME = 'index_captain_documents_on_assistant_id_and_external_link'.freeze
  NEW_INDEX_NAME = 'idx_captain_documents_on_assistant_id_and_external_link_md5'.freeze

  def up
    remove_external_link_indexes
    execute_null_external_link_backfill
    change_column :captain_documents, :external_link, :text, null: false
    add_index :captain_documents, 'assistant_id, md5(external_link)', unique: true, name: NEW_INDEX_NAME, if_not_exists: true
  end

  def down
    remove_index :captain_documents, name: NEW_INDEX_NAME, if_exists: true
    change_column :captain_documents, :external_link, :string, null: false
    add_index :captain_documents, [:assistant_id, :external_link], unique: true, name: OLD_INDEX_NAME, if_not_exists: true
  end

  private

  def remove_external_link_indexes
    indexes(:captain_documents).each do |index|
      next unless index.name == OLD_INDEX_NAME || index.columns.include?('external_link')

      remove_index :captain_documents, name: index.name, if_exists: true
    end
  end

  def execute_null_external_link_backfill
    execute <<~SQL.squish
      UPDATE captain_documents
      SET external_link = CONCAT('PDF: migrated_', id)
      WHERE external_link IS NULL
    SQL
  end
end
