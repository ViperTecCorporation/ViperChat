# Also loaded by standalone migrations before Rails defines the namespace.
module Conversations # rubocop:disable Style/ClassAndModuleChildren
  module HistoryMerge
    CONVERSATION_ARCHIVE = 'conversation_identity_repair_audits'.freeze

    class Conflict < StandardError; end

    private

    def execute(sql)
      connection.execute(sql)
    end

    def rows(sql)
      connection.select_all(sql).to_a
    end

    def q(value)
      connection.quote(value)
    end

    def qt(value)
      connection.quote_table_name(value)
    end

    def table_exists?(name)
      connection.table_exists?(name)
    end

    def column_exists?(table, name)
      connection.column_exists?(table, name)
    end

    def archive(table, predicate, retained_id = nil)
      execute <<~SQL.squish
        INSERT INTO #{CONVERSATION_ARCHIVE}(source_table,source_id,original_row,retained_id)
        SELECT #{q(table)},t.id,to_jsonb(t),#{retained_id || 'NULL'} FROM #{qt(table)} t WHERE #{predicate}
        ON CONFLICT (source_table,source_id) DO NOTHING
      SQL
    end

    def merge_conversation(old, keep)
      ensure_current_state_preserved!(old)
      archive('conversations', "id IN (#{old},#{keep})", keep)
      @references.each do |table, column, discriminator|
        next unless discriminator || column.end_with?('conversation_id')

        condition = "#{qt(column)}=#{old}"
        condition += " AND #{qt(discriminator)}='Conversation'" if discriminator
        next unless connection.select_value("SELECT EXISTS(SELECT 1 FROM #{qt(table)} WHERE #{condition})")

        archive(table, condition, keep)
        if %w[conversation_participants mentions group_contacts taggings].include?(table)
          # Keep the current membership/access/labels exactly as they are; retain the old state in the audit.
          execute "DELETE FROM #{qt(table)} WHERE #{condition}"
          next
        end
        collapse_conversation_memberships(table, column, discriminator, old, keep)
        execute "UPDATE #{qt(table)} SET #{qt(column)}=#{keep} WHERE #{condition}"
      end
      remap_user_preferences(old)
      remove_conversation(old)
    end

    def remove_conversation(id)
      execute "DELETE FROM conversations WHERE id=#{id}"
    end

    def ensure_current_state_preserved!(old)
      %w[applied_slas csat_survey_responses].each do |table|
        next unless table_exists?(table)
        next unless connection.select_value("SELECT EXISTS(SELECT 1 FROM #{qt(table)} WHERE conversation_id=#{old})")

        raise Conflict, "Historical #{table} requires separate retention; keeping conversations separate"
      end
    end

    def remap_user_preferences(old)
      old_conversation = rows("SELECT account_id,display_id FROM conversations WHERE id=#{old}").first
      account = old_conversation['account_id'].to_s
      old_display_id = old_conversation['display_id'].to_i
      rows("SELECT id,ui_settings FROM users WHERE ui_settings ?| array['pinned_conversations','archived_conversations']").each do |user|
        settings = user['ui_settings'].is_a?(String) ? JSON.parse(user['ui_settings']) : user['ui_settings']
        next unless replace_preference_ids(settings, account, old_display_id)

        archive('users', "id=#{user['id']}")
        execute "UPDATE users SET ui_settings=#{q(settings.to_json)} WHERE id=#{user['id']}"
      end
    end

    def replace_preference_ids(settings, account, old_id)
      changed = false
      %w[pinned_conversations archived_conversations].each do |key|
        ids = settings.dig(key, account)
        next unless ids.is_a?(Array) && ids.map(&:to_i).include?(old_id)

        settings[key][account] = ids.reject { |id| id.to_i == old_id }
        changed = true
      end
      changed
    end

    def collapse_conversation_memberships(table, column, discriminator, old, keep)
      return unless table == 'active_storage_attachments'

      equality = %w[record_type name blob_id].map { |key| "a.#{qt(key)} IS NOT DISTINCT FROM b.#{qt(key)}" }.join(' AND ')
      predicate = "a.#{qt(column)}=#{old} AND b.#{qt(column)}=#{keep} AND #{equality}"
      predicate += " AND a.#{qt(discriminator)}='Conversation'" if discriminator
      execute "DELETE FROM #{qt(table)} a USING #{qt(table)} b WHERE #{predicate}"
    end

    def refresh_label_counters
      return unless table_exists?('tags') && column_exists?('tags', 'taggings_count')

      predicate = "id IN (SELECT (original_row->>'tag_id')::bigint FROM #{CONVERSATION_ARCHIVE} WHERE source_table='taggings')"
      archive('tags', predicate)
      execute "UPDATE tags SET taggings_count=(SELECT count(*) FROM taggings WHERE tag_id=tags.id) WHERE #{predicate}"
    end
  end
end
