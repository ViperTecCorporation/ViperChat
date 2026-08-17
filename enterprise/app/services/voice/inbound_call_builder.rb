class Voice::InboundCallBuilder
  attr_reader :account, :inbox, :from_number, :call_sid, :provider, :extra_meta

  def self.perform!(**attributes)
    new(**attributes).perform!
  end

  def initialize(**attributes)
    @inbox = attributes.fetch(:inbox)
    @from_number = attributes.fetch(:from_number)
    @call_sid = attributes.fetch(:call_sid)
    @provider = attributes.fetch(:provider, :twilio).to_sym
    @extra_meta = attributes.fetch(:extra_meta, {}) || {}
    @legacy_conversation_mode = attributes[:account].present? && provider == :twilio
    @account = attributes[:account] || inbox.account
  end

  def perform!
    return perform_provider_call! unless @legacy_conversation_mode

    Rails.logger.info(
      "VOICE_INBOUND_CALL_BUILDER start account_id=#{account.id} inbox_id=#{inbox.id} call_sid=#{call_sid} from_number=#{from_number}"
    )
    timestamp = current_timestamp

    ActiveRecord::Base.transaction do
      contact = ensure_contact!
      contact_inbox = ensure_contact_inbox!(contact)
      conversation = find_conversation(contact_inbox) || create_conversation!(contact, contact_inbox)
      conversation.reload
      Rails.logger.info(
        "VOICE_INBOUND_CALL_BUILDER conversation account_id=#{account.id} conversation_id=#{conversation.display_id} call_sid=#{call_sid}"
      )
      update_conversation!(conversation, timestamp)
      build_voice_message!(conversation, timestamp)
      conversation
    end
  end

  private

  def perform_provider_call!
    existing = find_existing_provider_call
    return existing if existing

    ActiveRecord::Base.transaction do
      contact_inbox = ensure_provider_contact_inbox!
      contact = contact_inbox.contact
      conversation = resolve_provider_conversation!(contact, contact_inbox)
      call = create_provider_call!(contact, conversation)
      message = Voice::CallMessageBuilder.new(call).perform!
      call.update!(message_id: message.id)
      call
    end
  rescue ActiveRecord::RecordNotUnique
    find_existing_provider_call || raise
  end

  def find_existing_provider_call
    Call.where(account_id: account.id, inbox_id: inbox.id)
        .find_by(provider: provider, provider_call_id: call_sid)
  end

  def ensure_provider_contact_inbox!
    source_id = provider_source_id
    existing = inbox.contact_inboxes.find_by(source_id: source_id)
    return existing if existing

    ContactInbox.create!(contact: ensure_provider_contact!, inbox: inbox, source_id: source_id)
  rescue ActiveRecord::RecordNotUnique
    inbox.contact_inboxes.find_by!(source_id: source_id)
  end

  def ensure_provider_contact!
    contact = account.contacts.find_or_create_by!(phone_number: from_number) do |record|
      record.name = provider_contact_name.presence || from_number
    end
    contact.update!(name: provider_contact_name) if provider_contact_name.present? && contact.name == from_number
    contact
  end

  def provider_contact_name
    extra_meta.stringify_keys['contact_name'].presence
  end

  def provider_source_id
    return from_number unless provider == :whatsapp

    digits = from_number.to_s.delete_prefix('+')
    Whatsapp::PhoneNumberNormalizationService.new(inbox).normalize_and_find_contact_by_provider(digits, :cloud)
  end

  def resolve_provider_conversation!(contact, contact_inbox)
    reusable = if inbox.lock_to_single_conversation
                 contact_inbox.conversations.last
               else
                 contact_inbox.conversations.where.not(status: :resolved).last
               end
    return reusable if reusable

    account.conversations.create!(
      contact_inbox_id: contact_inbox.id,
      inbox_id: inbox.id,
      contact_id: contact.id,
      status: :open
    )
  end

  def create_provider_call!(contact, conversation)
    call = Call.create!(
      account: account,
      inbox: inbox,
      conversation: conversation,
      contact: contact,
      provider: provider,
      direction: :incoming,
      status: 'ringing',
      provider_call_id: call_sid,
      meta: { 'initiated_at' => Time.zone.now.to_i }.merge(extra_meta.stringify_keys)
    )
    call.update!(conference_sid: call.default_conference_sid) if call.twilio?
    call
  end

  def ensure_contact!
    contact = account.contacts.find_or_create_by!(phone_number: from_number) do |record|
      record.name = from_number if record.name.blank?
    end
    if contact.name.blank? && from_number.present?
      contact.update!(name: from_number)
    end
    contact
  end

  def ensure_contact_inbox!(contact)
    ContactInbox.find_or_create_by!(
      contact_id: contact.id,
      inbox_id: inbox.id
    ) do |record|
      record.source_id = from_number
    end
  end

  def find_conversation(contact_inbox)
    if call_sid.present?
      existing = account.conversations.includes(:contact).find_by(identifier: call_sid)
      return existing if existing.present?
    end

    return unless inbox.lock_to_single_conversation?

    contact_inbox.conversations.last
  end

  def create_conversation!(contact, contact_inbox)
    account.conversations.create!(
      contact_inbox_id: contact_inbox.id,
      inbox_id: inbox.id,
      contact_id: contact.id,
      status: :open,
      identifier: call_sid
    )
  end

  def update_conversation!(conversation, timestamp)
    attrs = {
      'call_direction' => 'inbound',
      'call_status' => 'ringing',
      'conference_sid' => Voice::Conference::Name.for(conversation),
      'voice_inbox_id' => inbox.id,
      'meta' => { 'initiated_at' => timestamp }
    }

    conversation.update!(
      identifier: call_sid,
      additional_attributes: attrs,
      last_activity_at: current_time
    )
  end

  def build_voice_message!(conversation, timestamp)
    Voice::CallMessageBuilder.perform!(
      conversation: conversation,
      direction: 'inbound',
      payload: {
        call_sid: call_sid,
        status: 'ringing',
        voice_inbox_id: inbox.id,
        conference_sid: conversation.additional_attributes['conference_sid'],
        from_number: from_number,
        to_number: inbox.channel&.phone_number
      },
      timestamps: { created_at: timestamp, ringing_at: timestamp }
    )
  end

  def current_timestamp
    @current_timestamp ||= current_time.to_i
  end

  def current_time
    @current_time ||= Time.zone.now
  end
end
