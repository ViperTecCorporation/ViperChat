# Only a pristine placeholder created by this feature can be consolidated.
# Never use ContactMergeAction: it runs callbacks and can overwrite human data.
class Whatsapp::ProvisionalIdentityContactService
  attr_reader :status

  def self.snapshot(contact)
    contact.attributes.except('id', 'created_at', 'updated_at', 'last_activity_at')
  end

  def initialize(link:, contact:)
    @link = link
    @contact = contact
    @status = 'alias_conflict'
  end

  def perform
    @link.lock!
    origin = owned_origin
    return false unless origin

    provisional = @link.contact
    Contact.where(id: [provisional.id, @contact.id]).order(:id).lock.load
    @status = 'provisional_enriched'
    return false unless self.class.snapshot(provisional.reload) == origin.provisional_snapshot && safe_dependencies?(provisional)

    consolidate(provisional)
    true
  end

  private

  def owned_origin
    origin_id = @link.additional_attributes['identity_provisional_resolution_id']
    origin = WhatsappIdentityResolution.find_by(id: origin_id, provisional_contact_id: @link.contact_id)
    return unless origin && origin.whatsapp_message_identity.inbox_id == @link.inbox_id
    return unless @link.contact.account_id == @contact.account_id && @contact.account_id == @link.inbox.account_id

    origin
  end

  def consolidate(provisional)
    # No callbacks: existing delivery/read/status, assignment, notes, attachments,
    # schedules and conversation IDs stay untouched. No domain events replayed.
    @link.conversations.update_all(contact_id: @contact.id) # rubocop:disable Rails/SkipsModelValidations
    Message.where(sender: provisional).update_all(sender_id: @contact.id) # rubocop:disable Rails/SkipsModelValidations
    @link.update!(contact_id: @contact.id)
    WhatsappIdentityResolution.where(provisional_contact_id: provisional.id).update_all(resolved_contact_id: @contact.id) # rubocop:disable Rails/SkipsModelValidations
    provisional.delete
  end

  def safe_dependencies?(provisional)
    return false unless provisional.contact_inboxes.pluck(:id) == [@link.id]
    return false if provisional.conversations.exists?(['inbox_id != ? OR contact_inbox_id IS DISTINCT FROM ?', @link.inbox_id, @link.id])
    return false if provisional.conversations.exists?(group: true)
    return false if Message.where(sender: provisional).where.not(conversation_id: @link.conversations.select(:id)).exists?

    # Deny unknown/Enterprise dependencies rather than silently losing them.
    ActiveRecord::Base.connection.tables.all? { |table| table_safe?(table, provisional.id) }
  end

  def table_safe?(table, id)
    definition = ActiveRecord::Base.connection.schema_cache.columns_hash(table).values
    columns = definition.map(&:name)
    types = definition.select { |column| %i[string text].include?(column.type) }.map(&:name)
    contact_reference_safe?(table, columns, id) && polymorphic_references_safe?(table, columns, types, id)
  end

  def contact_reference_safe?(table, columns, id)
    return true unless columns.include?('contact_id')
    return true if %w[conversations contact_inboxes].include?(table)

    connection = ActiveRecord::Base.connection
    !connection.select_value("SELECT 1 FROM #{connection.quote_table_name(table)} WHERE contact_id = '#{Integer(id)}' LIMIT 1")
  end

  def polymorphic_references_safe?(table, columns, types, id)
    connection = ActiveRecord::Base.connection
    types.grep(/_type\z/).all? do |type|
      key = type.sub(/_type\z/, '_id')
      next true unless columns.include?(key)
      next true if table == 'messages' && type == 'sender_type'

      !connection.select_value("SELECT 1 FROM #{connection.quote_table_name(table)} WHERE #{connection.quote_column_name(type)} = 'Contact' " \
                               "AND #{connection.quote_column_name(key)} = '#{Integer(id)}' LIMIT 1")
    end
  end
end
