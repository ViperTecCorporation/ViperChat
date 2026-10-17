# Reconciles only proven, post-activation, single-item copies. Public Message,
# Attachment and ActiveStorage::Attachment IDs survive the blob substitution.
class Whatsapp::UnifiedMediaReconciliationService
  Result = Struct.new(:status, :reason, :message_ids, :attachment_ids, keyword_init: true)
  MEDIA_TYPES = { 'image' => 'image/', 'sticker' => 'image/', 'audio' => 'audio/', 'video' => 'video/', 'document' => '*' }.freeze

  # Register with the outermost transaction: returning from a savepoint is not a
  # commit, and a later rollback must never enqueue deletion of the old blob.
  class PurgeAfterCommit # rubocop:disable Style/OneClassPerFile
    def initialize(blob_ids)
      @blob_ids = blob_ids
    end

    def trigger_transactional_callbacks?
      false
    end

    def before_committed!(**); end
    def rolledback!(**); end

    def committed!(**)
      ActiveStorage::Blob.where(id: @blob_ids).order(:id).each do |blob|
        blob.with_lock do
          next unless Whatsapp::UnifiedMediaBlobPurgeService.unreferenced?(blob)

          Whatsapp::PurgeUnifiedMediaBlobJob.perform_later(blob.id)
        end
      end
    end
  end

  def initialize(record:)
    @record = record
  end

  def perform
    @messages = []
    @attachments = []
    @link = WhatsappInboxLink.find(@record.whatsapp_inbox_link_id)
    @link.with_lock(requires_new: true) do
      @record.lock!
      next result(:rejected, :link_disabled) unless @link.enabled? && @link.activated_at
      next result(:review, :invalid_scope) unless @link.valid?

      @identities = @record.identities.order(:id).lock.to_a
      next result(:pending, :counterpart_pending) if pending_counterpart?
      next result(:review, :untrusted_mapping) unless trusted_pair?

      reconcile_messages
    end
  end

  private

  def reconcile_messages
    @messages = Message.where(id: copy_ids).order(:id).lock.to_a
    return result(:review, :incompatible_messages) unless compatible_messages?

    reconcile
  end

  def pending_counterpart?
    return false unless @identities.one?

    identity = @identities.first
    comparison = Whatsapp::MessageIdentityCorrelationService.new(identity: identity, partner_inbox: @link.partner_for(identity.inbox))
    identity.account_id == @link.account_id && [@link.primary_inbox_id, @link.secondary_inbox_id].include?(identity.inbox_id) &&
      identity.provider_message_id == @record.original_id && matching_observation?(identity) &&
      recognized_mapping?(identity) && comparison.safe_for_unification?
  end

  def trusted_pair?
    return false unless @identities.size == 2 && @identities.map(&:inbox_id).sort == [@link.primary_inbox_id, @link.secondary_inbox_id].sort

    @identities.all? { |identity| trusted_identity?(identity) }
  end

  def trusted_identity?(identity)
    comparison = Whatsapp::MessageIdentityCorrelationService.new(identity: identity, partner_inbox: @link.partner_for(identity.inbox))
    identity.account_id == @link.account_id && identity.provider_message_id == @record.original_id &&
      matching_observation?(identity) && comparison.perform[:status] == 'matched' &&
      comparison.comparison_participant == @record.participant_key && recognized_mapping?(identity)
  end

  def matching_observation?(identity)
    observations = identity.observations
    timestamp = observations['timestamp'].to_s
    observations['direction'] == @record.direction && observations['message_type'] == @record.message_kind &&
      timestamp.match?(/\A\d+\z/) && Time.zone.at(timestamp.to_i) >= @link.activated_at
  end

  def recognized_mapping?(identity)
    return true if identity.provider == 'unoapi'

    parsed = Whatsapp::MetaMessageIdAdapter.parse(identity.external_id)
    identity.observations.dig('meta_id_adapter', 'status') == 'recognized' &&
      parsed && parsed['provider_message_id'] == @record.original_id && parsed['direction'] == @record.direction
  end

  def copy_ids
    WhatsappMessageIdentityLink.where(whatsapp_message_identity_id: @identities.map(&:id)).lock.pluck(:message_id) |
      @record.aliases.lock.pluck(:message_id).compact | [@record.message_id].compact
  end

  def compatible_messages?
    return false if @messages.empty? || @record.message_id.blank?
    return false unless same_known_contact?

    @messages.all? { |message| public_scoped_message?(message) && matching_contact?(message) }
  end

  def same_known_contact?
    contacts = @messages.map { |message| message.conversation.contact }
    contacts.map(&:id).uniq.one? && contacts.all? { |contact| contact.account_id == @link.account_id }
  end

  def public_scoped_message?(message)
    message.account_id == @link.account_id && @link.covers?(message.inbox) &&
      message.conversation.account_id == @link.account_id && message.conversation.inbox_id == message.inbox_id &&
      public_current_message?(message)
  end

  def public_current_message?(message)
    !message.private? && !message.web_attendance? && message.message_type == @record.direction && message.created_at >= @link.activated_at
  end

  def matching_contact?(message)
    @identities.all? do |identity|
      comparison = Whatsapp::MessageIdentityCorrelationService.new(identity: identity, partner_inbox: @link.partner_for(identity.inbox))
      comparison.contact_matches_participant?(message.conversation.contact)
    end
  end

  def reconcile
    return result(:review, :unsupported_media) unless MEDIA_TYPES.key?(@record.message_kind)

    @attachments = Attachment.where(message_id: @messages.map(&:id)).order(:id).lock.to_a
    issue = attachment_issue
    return issue if issue

    files = ActiveStorage::Attachment.where(record_type: 'Attachment', record_id: @attachments.map(&:id), name: 'file').order(:id).lock.to_a
    return result(:pending, :media_unavailable) unless single_file_per_attachment?(files)

    reconcile_files(files)
  end

  def attachment_issue
    return result(:review, :attachment_count) unless @messages.all? { |message| @attachments.count { |item| item.message_id == message.id } == 1 }
    return result(:review, :attachment_scope) unless @attachments.all? { |item| item.account_id == @link.account_id }

    nil
  end

  def single_file_per_attachment?(files)
    @attachments.all? { |item| files.count { |file| file.record_id == item.id } == 1 }
  end

  def reconcile_files(files)
    blobs = ActiveStorage::Blob.where(id: files.map(&:blob_id)).order(:id).lock.index_by(&:id)
    return result(:review, :media_mismatch) unless compatible_files?(files, blobs)

    # Single ingestion deliberately downloads only the first arriving copy.
    # Proven aliases for both providers do not imply a second stored file.
    # Keep that file and its truthful origin; a later real principal copy still
    # follows the normal replacement/purge path below.
    return retain_single_copy(blobs.fetch(files.first.blob_id)) if single_canonical_copy?(files)

    winner = available_principal_blob(files, blobs)
    return result(:pending, :principal_unavailable) unless winner

    replace_blobs(files, winner)
  end

  def single_canonical_copy?(files)
    @messages.one? && @messages.first.id == @record.message_id && @messages.first.inbox_id == @link.primary_inbox_id && files.one?
  end

  def retain_single_copy(blob)
    return result(:pending, :media_unavailable) unless blob.byte_size.positive? && blob.service.exist?(blob.key)

    result(:unchanged, :single_copy_retained)
  end

  def available_principal_blob(files, blobs)
    principal_ids = principal_attachments.map(&:id)
    winners = files.select { |file| principal_ids.include?(file.record_id) }.map(&:blob_id).uniq
    return unless winners.one?

    winner = blobs.fetch(winners.first)
    winner if winner.byte_size.positive? && winner.service.exist?(winner.key)
  end

  def principal_attachments
    @attachments.select do |item|
      message = @messages.find { |copy| copy.id == item.message_id }
      message.inbox_id == @link.primary_inbox_id &&
        (message.id != @record.message_id || @record.media_inbox_id.nil? || @record.media_inbox_id == @link.primary_inbox_id)
    end
  end

  def compatible_files?(files, blobs)
    types = { 'image' => 'image', 'sticker' => 'image', 'audio' => 'audio', 'video' => 'video', 'document' => 'file' }
    expected_type = types.fetch(@record.message_kind)
    @attachments.all? { |item| item.file_type == expected_type && item.external_url.blank? } && files.all? do |file|
      blob = blobs.fetch(file.blob_id)
      expected = MEDIA_TYPES.fetch(@record.message_kind)
      expected == '*' ? blob.content_type.present? : blob.content_type.to_s.start_with?(expected)
    end
  end

  def replace_blobs(files, winner)
    replaced = files.reject { |file| file.blob_id == winner.id }
    old_ids = replaced.map(&:blob_id).uniq
    # Updating the existing AS row avoids has_one_attached's destroy/purge path.
    replaced.each { |file| file.update!(blob: winner) }
    @record.update!(media_inbox_id: @link.primary_inbox_id) unless @record.media_inbox_id == @link.primary_inbox_id
    ActiveRecord::Base.connection.add_transaction_record(PurgeAfterCommit.new(old_ids)) if old_ids.any?
    result(replaced.any? ? :reconciled : :unchanged, nil)
  end

  def result(status, reason)
    Result.new(status: status, reason: reason, message_ids: @messages.map(&:id), attachment_ids: @attachments.map(&:id))
  end
end
