class RepurposeQuotedEmailReplyFlagForUnreadCountForFilters < ActiveRecord::Migration[7.1]
  QUOTED_EMAIL_REPLY_BIT = 1 << 5

  def up
    # The quoted_email_reply flag (deprecated) has been renamed to unread_count_for_filters.
    # Disable it on any accounts that had quoted_email_reply enabled so the repurposed
    # flag starts in its intended default-off state.
    clear_repurposed_flag

    # Remove the stale quoted_email_reply entry from ACCOUNT_LEVEL_FEATURE_DEFAULTS.
    # ConfigLoader only adds new flags; it never removes renamed ones.
    # Leaving it would cause NoMethodError in enable_default_features when
    # creating new accounts (feature_quoted_email_reply= no longer exists).
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return if config&.value.blank?

    config.value = config.value.reject { |feature| feature['name'] == 'quoted_email_reply' }
    config.save!
    GlobalConfig.clear_cache
  end

  private

  def clear_repurposed_flag
    column = if column_exists?(:accounts, :feature_flags_ext_1)
               :feature_flags_ext_1
             elsif column_exists?(:accounts, :feature_flags_2)
               :feature_flags_2
             end
    return if column.blank?

    execute <<~SQL.squish
      UPDATE accounts
      SET #{column} = #{column} & ~#{QUOTED_EMAIL_REPLY_BIT}::bigint
      WHERE (#{column} & #{QUOTED_EMAIL_REPLY_BIT}::bigint) != 0
    SQL
  end
end
