require 'digest'

# Explicit administrator maintenance, not a webhook merge. Never deletes a row,
# moves a message between conversations, purges a blob or replaces a public ID.
class Whatsapp::ContactReconciliationService
  def initialize(link:, pairs:)
    @link = link
    @pairs = pairs.map { |legacy, canonical| [Integer(legacy), Integer(canonical)] }
  end

  def preview
    rows = @pairs.map { |legacy, canonical| preview_pair(legacy, canonical) }
    { pairs: rows, blocked: rows.any? { |row| row[:blockers].present? },
      fingerprint: Digest::SHA256.hexdigest(rows.to_json),
      deletes: 0, message_moves: 0, media_changes: 0 }
  end

  def apply!(fingerprint:)
    @link.account.with_lock do
      Inbox.where(id: [@link.primary_inbox_id, @link.secondary_inbox_id]).order(:id).lock.load
      Contact.where(id: @pairs.flatten).order(:id).lock.load
      before = preview
      raise ArgumentError, 'Reconciliation preview is blocked' if before[:blocked]
      raise ArgumentError, 'Reconciliation preview changed; review again' unless fingerprint == before[:fingerprint]

      @pairs.each { |legacy, canonical| reconcile_pair(legacy, canonical) }
      before.merge(applied: true)
    end
  end

  private

  def preview_pair(legacy_id, canonical_id)
    legacy = @link.account.contacts.find(legacy_id)
    canonical = @link.account.contacts.find(canonical_id)
    aliases = legacy.contact_inboxes.order(:id).pluck(:id, :inbox_id, :source_id)
    conversations = legacy.conversations.order(:id).pluck(:id, :inbox_id)
    blockers = scope_blockers(legacy, canonical, aliases, conversations)
    blockers.concat(other_references(legacy.id))
    { legacy_contact_id: legacy.id, canonical_contact_id: canonical.id, canonical_name: canonical.name,
      aliases: aliases, conversations: conversations,
      **message_inventory(legacy, conversations), blockers: blockers }
  end

  def message_inventory(legacy, conversations)
    { message_ids: Message.where(conversation_id: conversations.map(&:first)).order(:id).pluck(:id),
      sender_message_ids: Message.where(sender_type: 'Contact', sender_id: legacy.id).order(:id).pluck(:id),
      attachment_ids: Attachment.where(message_id: Message.where(conversation_id: conversations.map(&:first)).select(:id)).order(:id).pluck(:id) }
  end

  def scope_blockers(legacy, canonical, aliases, conversations)
    boxes = [@link.primary_inbox_id, @link.secondary_inbox_id]
    checks = {
      'link_disabled' => !@link.reload.enabled?,
      'not_an_older_phone_contact' => !older_phone_contact?(legacy, canonical),
      'phone_evidence_conflict' => !phone_evidence?(canonical, aliases),
      'bsuid_alias_missing' => !bsuid_alias?(legacy, aliases),
      'outside_link_scope' => outside_scope?(aliases, conversations, boxes),
      'group_conversation' => legacy.conversations.exists?(group: true),
      'sender_outside_link_scope' => Message.where(sender_type: 'Contact', sender_id: legacy.id).where.not(inbox_id: boxes).exists?,
      'canonical_alias_missing' => !canonical.contact_inboxes.exists?(inbox_id: boxes)
    }
    checks.filter_map { |reason, failed| reason if failed }
  end

  def outside_scope?(aliases, conversations, boxes)
    (aliases.pluck(1) + conversations.pluck(1) - boxes).present?
  end

  def older_phone_contact?(legacy, canonical)
    canonical.phone_number.present? && legacy.phone_number.blank? && canonical.created_at < legacy.created_at
  end

  def phone_evidence?(canonical, aliases)
    meta = @link.inbox_for('whatsapp_cloud')
    phones = aliases.select { |row| row[1] == meta.id }.filter_map { |row| Whatsapp::InboxLinkPhoneService.normalize(row[2]) }.uniq
    expected = Whatsapp::InboxLinkPhoneService.normalize(canonical.phone_number)
    expected.present? && phones == [expected]
  end

  def bsuid_alias?(legacy, aliases)
    meta = @link.inbox_for('whatsapp_cloud')
    legacy.bsuid.to_s.start_with?('BR.') && aliases.any? { |row| row[1] == meta.id && row[2] == legacy.bsuid }
  end

  def other_references(contact_id)
    connection = ActiveRecord::Base.connection
    columns = connection.select_rows(<<~SQL.squish)
      SELECT table_name, column_name FROM information_schema.columns
      WHERE table_schema = current_schema() AND
      (column_name = 'contact_id' OR column_name IN ('provisional_contact_id', 'resolved_contact_id'))
      ORDER BY table_name, column_name
    SQL
    columns.filter_map do |table, column|
      next if %w[contact_inboxes conversations].include?(table) && column == 'contact_id'

      found = connection.select_value("SELECT 1 FROM #{connection.quote_table_name(table)} " \
                                      "WHERE #{connection.quote_column_name(column)} = #{Integer(contact_id)} LIMIT 1")
      "dependent_reference:#{table}.#{column}" if found
    end
  end

  def reconcile_pair(legacy, canonical)
    ContactInbox.where(contact_id: legacy).update_all(contact_id: canonical) # rubocop:disable Rails/SkipsModelValidations
    Conversation.where(contact_id: legacy).update_all(contact_id: canonical) # rubocop:disable Rails/SkipsModelValidations
    Message.where(sender_type: 'Contact', sender_id: legacy).update_all(sender_id: canonical) # rubocop:disable Rails/SkipsModelValidations
    raise 'Legacy contact was not preserved' unless @link.account.contacts.exists?(legacy)
    raise 'Unreconciled aliases remain' if ContactInbox.exists?(contact_id: legacy)
    raise 'Unreconciled conversations remain' if Conversation.exists?(contact_id: legacy)
  end
end
