class Voice::OutboundCallBuilder
  attr_reader :account, :inbox, :user, :contact

  def self.perform!(account:, inbox:, user:, contact:)
    new(account: account, inbox: inbox, user: user, contact: contact).perform!
  end

  def initialize(account:, inbox:, user:, contact:)
    @account = account
    @inbox = inbox
    @user = user
    @contact = contact
  end

  def perform!
    if contact.name.blank? && contact.phone_number.present?
      contact.update!(name: contact.phone_number)
    end
    raise ArgumentError, 'Contact phone number required' if contact.phone_number.blank?
    raise ArgumentError, 'Agent required' if user.blank?

    Rails.logger.info(
      "VOICE_OUTBOUND_CALL_BUILDER start account_id=#{account.id} inbox_id=#{inbox.id} contact_id=#{contact.id} user_id=#{user.id}"
    )
    timestamp = current_timestamp
    log_channel_context

    ActiveRecord::Base.transaction do
      contact_inbox = ensure_contact_inbox!
      conversation = create_conversation!(contact_inbox)
      conversation.reload
      conference_sid = Voice::Conference::Name.for(conversation)
      call_sid = initiate_call!
      Rails.logger.info(
        "VOICE_OUTBOUND_CALL_BUILDER initiated " \
        "account_id=#{account.id} " \
        "conversation_id=#{conversation.display_id} " \
        "call_sid=#{call_sid} " \
        "conference_sid=#{conference_sid}"
      )
      update_conversation!(conversation, call_sid, conference_sid, timestamp)
      build_voice_message!(conversation, call_sid, conference_sid, timestamp)
      { conversation: conversation, call_sid: call_sid }
    end
  rescue StandardError => e
    Rails.logger.error(
      "VOICE_OUTBOUND_CALL_BUILDER error class=#{e.class} message=#{e.message} " \
      "backtrace=#{e.backtrace&.first(12)}"
    )
    raise
  end

  private

  def ensure_contact_inbox!
    ContactInbox.find_or_create_by!(
      contact_id: contact.id,
      inbox_id: inbox.id
    ) do |record|
      record.source_id = contact.phone_number
    end
  end

  def create_conversation!(contact_inbox)
    if inbox.lock_to_single_conversation?
      existing = contact_inbox.conversations.last
      return existing if existing.present?
    end

    account.conversations.create!(
      contact_inbox_id: contact_inbox.id,
      inbox_id: inbox.id,
      contact_id: contact.id,
      status: :open
    )
  end

  def initiate_call!
    inbox.channel.initiate_call(
      to: contact.phone_number
    )[:call_sid]
  end

  def update_conversation!(conversation, call_sid, conference_sid, timestamp)
    attrs = {
      'call_direction' => 'outbound',
      'call_status' => 'ringing',
      'agent_id' => user.id,
      'conference_sid' => conference_sid,
      'voice_inbox_id' => inbox.id,
      'meta' => { 'initiated_at' => timestamp }
    }

    conversation.update!(
      identifier: call_sid,
      additional_attributes: attrs,
      last_activity_at: current_time
    )
  end

  def build_voice_message!(conversation, call_sid, conference_sid, timestamp)
    Voice::CallMessageBuilder.perform!(
      conversation: conversation,
      direction: 'outbound',
      payload: {
        call_sid: call_sid,
        status: 'ringing',
        voice_inbox_id: inbox.id,
        conference_sid: conference_sid,
        from_number: inbox.channel&.phone_number,
        to_number: contact.phone_number
      },
      user: user,
      timestamps: { created_at: timestamp, ringing_at: timestamp }
    )
  end

  def current_timestamp
    @current_timestamp ||= current_time.to_i
  end

  def current_time
    @current_time ||= Time.zone.now
  end

  def log_channel_context
    channel = inbox&.channel
    Rails.logger.info(
      "VOICE_OUTBOUND_CALL_BUILDER channel " \
      "channel_class=#{channel&.class} " \
      "channel_id=#{channel&.id} " \
      "provider=#{channel_provider(channel)} " \
      "provider_config_class=#{channel_provider_config_class(channel)}"
    )
  end

  def channel_provider(channel)
    return channel.provider if channel&.respond_to?(:provider)

    'twilio'
  end

  def channel_provider_config_class(channel)
    return unless channel&.respond_to?(:provider_config)

    channel.provider_config.class
  end
end
