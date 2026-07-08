class AddFeatureFlagsExt2ToAccounts < ActiveRecord::Migration[7.0]
  def up
    add_column :accounts, :feature_flags_ext_1, :bigint, default: 0, null: false

    return unless column_exists?(:accounts, :feature_flags_2)

    execute <<~SQL.squish
      UPDATE accounts
      SET feature_flags_ext_1 = feature_flags_2
    SQL
  end

  def down
    remove_column :accounts, :feature_flags_ext_1
  end
end
