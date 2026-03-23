# Mostly modeled after the intial implementation of the service based on 360 Dialog
# https://docs.360dialog.com/whatsapp-api/whatsapp-api/media
# https://developers.facebook.com/docs/whatsapp/api/media/
class Whatsapp::IncomingMessageBaseService
  include ::Whatsapp::IncomingMessageServiceHelpers

  # rubocop:disable Style/ClassVars
  @@microsecond = 0
  # rubocop:enable Style/ClassVars

  pattr_initialize [:inbox!, :params!, :outgoing_echo]

  def perform
    processed_params

    if processed_params.try(:[], :statuses).present?
      process_statuses
    elsif contact_sync_payload?
      sync_contacts
    elsif messages_data.present?
      process_messages
    elsif processed_params.try(:[], :contacts).present?
      sync_contacts
    end
  end

  # Returns messages array for both regular messages and echo events
  def messages_data
    @processed_params&.dig(:messages) || @processed_params&.dig(:message_echoes)
  end

  private

  def process_messages
    # We don't support reactions & ephemeral message now, we need to skip processing the message
    # if the webhook event is a reaction or an ephermal message or an unsupported message.
    return if unprocessable_message_type?(message_type)

    # Multiple webhook events can be received for the same message due to
    # misconfigurations in the Meta business manager account.
    # We use an atomic Redis SET NX to prevent concurrent workers from both
    # processing the same message simultaneously.
    return if find_message_by_source_id(messages_data.first[:id])
    return unless lock_message_source_id!
    set_message_type
    set_contact
    return unless @contact

    ActiveRecord::Base.transaction do
      set_conversation
      create_messages
    end
  end

  def process_statuses
    return unless find_message_by_source_id(@processed_params[:statuses].first[:id])

    update_message_with_status(@message, @processed_params[:statuses].first)
  rescue ArgumentError => e
    Rails.logger.error "Error while processing whatsapp status update #{e.message}"
  end

  def contact_sync_payload?
    return false if processed_params.blank?
    return false if processed_params.try(:[], :contacts).blank?

    message = processed_params[:messages]&.first
    return false if message.blank?
    return false unless message[:type].to_s == 'text'

    message.dig(:text, :body).to_s.strip.casecmp('contacts.update').zero?
  end

  def sync_contacts
    processed_params[:contacts].each do |contact|
      sync_contact(contact)
    end
  end

  def sync_contact(contact_params)
    return if contact_params.blank?

    contact_attributes = {
      name: contact_params.dig(:profile, :name),
      avatar_url: contact_params.dig(:profile, :picture)
    }

    waid = contact_params[:wa_id].to_s
    profile_phone = contact_params.dig(:profile, :phone).to_s
    if waid.include?('@lid')
      contact_attributes[:email] = waid
      waid = nil
    else
      raw_phone = waid.presence || profile_phone
      raw_phone = raw_phone.gsub(/\D/, '')
      return if raw_phone.blank? || raw_phone == '0'
      return unless raw_phone.match?(/^[1-9]\d{7,14}$/)
      if raw_phone.present?
        waid = processed_waid(raw_phone) || raw_phone
        phone_number = brazil_phone_number?(raw_phone) ? normalised_brazil_mobile_number(raw_phone) : waid
        contact_attributes[:phone_number] = "+#{phone_number}" if phone_number.present?
      end
    end

    contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: waid,
      inbox: inbox,
      contact_attributes: contact_attributes
    ).perform

    @contact_inbox = contact_inbox
    @contact = contact_inbox.contact

    raw_from = waid.presence || profile_phone
    update_contact_with_profile_name(contact_params, raw_from: raw_from)
    sync_group_contact(contact_params)
  end

  def sync_group_contact(contact_params)
    return if contact_params[:group_id].blank?

    ::ContactInboxWithContactBuilder.new(
      source_id: contact_params[:group_id],
      inbox: inbox,
      contact_attributes: {
        email: contact_params[:group_id],
        name: contact_params[:group_subject] || contact_params[:group_id],
        avatar_url: contact_params[:group_picture]
      }
    ).perform
  end

  def update_message_with_status(message, status)
    if status[:status] == 'deleted'
      message.assign_attributes(content: I18n.t('conversations.messages.deleted'), content_attributes: { deleted: true })
    else
      message.status = status[:status]
    end
    if status[:status] == 'failed' && status[:errors].present?
      error = status[:errors]&.first
      message.external_error = "#{error[:code]}: #{error[:title]}"
      message.conversation.open! unless message.conversation.open?
    end
    message.save!
  end

  def create_messages
    message = messages_data.first
    log_error(message) && return if error_webhook_event?(message)

    process_in_reply_to(message)

    message_type == 'contacts' ? create_contact_messages(message) : create_regular_message(message)
  end

  def create_contact_messages(message)
    message['contacts'].each do |contact|
      # Pass source_id from parent message since contact objects don't have :id
      create_message(contact, source_id: message[:id])
      attach_contact(contact)
      @message.save!
    end
  end

  def create_regular_message(message)
    create_message(message, source_id: message[:id])
    attach_files
    attach_location if message_type == 'location'
    @message.save!
  end

  def set_contact
    if outgoing_echo
      set_contact_from_echo
    else
      set_contact_from_message
    end
  end

  def set_contact_from_echo
    # For echo messages, contact phone is in the 'to' field
    phone_number = messages_data.first[:to].to_s
    return if phone_number.blank?

    waid = processed_waid(phone_number) || phone_number

    contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: waid,
      inbox: inbox,
      contact_attributes: { name: "+#{phone_number}", phone_number: "+#{phone_number}" }
    ).perform

    @contact_inbox = contact_inbox
    @contact = contact_inbox.contact
    @sender = nil
  end

  def set_contact_from_message
    contact_params = @processed_params[:contacts]&.first
    return if contact_params.blank?

    waid = nil
    contact_attributes = { name: contact_params.dig(:profile, :name), avatar_url: contact_params.dig(:profile, :picture) }
    if lid_message?
      contact_attributes = contact_attributes.merge({ email: contact_params[:wa_id] })
    else
      clean_waid = contact_params[:wa_id].to_s.gsub(/\D/, '')
      waid = processed_waid(clean_waid) || clean_waid
      phone_number = brazil_phone_number?(clean_waid) ? normalised_brazil_mobile_number(clean_waid) : waid
      contact_attributes = contact_attributes.merge({ phone_number: "+#{phone_number}" })
    end
    contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: waid,
      inbox: inbox,
      contact_attributes: contact_attributes
    ).perform

    @contact_inbox = contact_inbox
    @contact = contact_inbox.contact
    @sender = webhook_outgoing_message? ? nil : contact_inbox.contact

    # Update existing contact name for LID-suffix placeholders or low-quality names
    update_contact_with_profile_name(contact_params)
  end

  def set_conversation
    # if lock to single conversation is disabled, we will create a new conversation if previous conversation is resolved
    @conversation = if @inbox.lock_to_single_conversation
                      @contact_inbox.conversations.last
                    else
                      @contact_inbox.conversations
                                    .where.not(status: :resolved).last
                    end
    return if @conversation

    @conversation = ::Conversation.create!(conversation_params)
  end

  def attach_files
    return if %w[text button interactive location contacts].include?(message_type)

    attachment_payload = messages_data.first[message_type.to_sym]
    @message.content ||= attachment_payload[:caption]

    attachment_file = download_attachment_file(attachment_payload)
    return if attachment_file.blank?

    @message.attachments.new(
      account_id: @message.account_id,
      file_type: file_content_type(message_type),
      file: {
        io: attachment_file,
        filename: attachment_file.original_filename,
        content_type: attachment_file.content_type
      }
    )
  end

  def attach_location
    location = messages_data.first['location']
    location_name = location['name'] ? "#{location['name']}, #{location['address']}" : ''
    @message.attachments.new(
      account_id: @message.account_id,
      file_type: file_content_type(message_type),
      coordinates_lat: location['latitude'],
      coordinates_long: location['longitude'],
      fallback_title: location_name,
      external_url: location['url']
    )
  end

  def create_message(message, source_id: nil)
    timestamp = message[:timestamp] ? Time.at(message[:timestamp].to_i, microsecond, :microsecond, in: 'UTC') : Time.current.utc
    Rails.logger.info("[WHATSAPP] Incoming message type=#{message_type} content_type=#{message_type == 'sticker' ? 'sticker' : 'nil'} source_id=#{message[:id]}")
    content_attrs = webhook_outgoing_message? ? { external_echo: true } : {}
    content_attrs[:in_reply_to_external_id] = @in_reply_to_external_id if @in_reply_to_external_id.present?

    @message = @conversation.messages.build(
      content: message_content(message),
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      message_type: webhook_outgoing_message? ? :outgoing : @message_type,
      # Set status to :delivered for echo messages to prevent SendReplyJob from trying to send them
      status: webhook_outgoing_message? ? :delivered : :sent,
      content_type: message_type == 'sticker' ? 'sticker' : nil,
      sender: webhook_outgoing_message? ? nil : @sender,
      source_id: (source_id || message[:id]).to_s,
      content_attributes: content_attrs,
      created_at: timestamp,
    )
    @message
  end

  def webhook_outgoing_message?
    outgoing_echo || @message_type == :outgoing
  end

  def attach_contact(contact)
    phones = contact[:phones]
    phones = [{ phone: 'Phone number is not available' }] if phones.blank?

    name_info = (contact[:name] || contact['name'] || {}).with_indifferent_access
    formatted_name = contact_formatted_name(name_info)
    contact_meta = {
      formattedName: formatted_name,
      firstName: name_info[:first_name].presence || name_info[:firstName],
      lastName: name_info[:last_name].presence || name_info[:lastName]
    }.compact

    update_shared_contact_name(contact, formatted_name)

    phones.each do |phone|
      @message.attachments.new(
        account_id: @message.account_id,
        file_type: file_content_type(message_type),
        fallback_title: phone[:phone].to_s,
        meta: contact_meta
      )
    end
  end

  def set_message_type
    @message_type = :incoming
  end

  def microsecond
    # rubocop:disable Style/ClassVars
    @@microsecond = 0 if @@microsecond > 999_999
    @@microsecond += 1
    @@microsecond
    # rubocop:enable Style/ClassVars
  end

  def contact_params
    @contact_params ||= @processed_params[:contacts]&.first
  end

  def lid_message?
    contact_params.present? && contact_params[:wa_id]&.include?('@lid')
  end

  def update_contact_with_profile_name(contact_params, raw_from: nil)
    profile_name = contact_params.dig(:profile, :name)
    return if profile_name.blank?
    return if @contact.name == profile_name

    return unless contact_name_updatable?(@contact, raw_from: raw_from)

    @contact.update!(name: profile_name)
  end

  def update_shared_contact_name(contact_payload, formatted_name)
    return if formatted_name.blank?

    normalized_contact_phone_numbers(contact_payload).each do |phone_number|
      shared_contact = Contact.find_by(account_id: @inbox.account_id, phone_number: phone_number)
      next if shared_contact.blank? || shared_contact.name == formatted_name
      next unless contact_name_updatable?(shared_contact, raw_from: phone_number)

      shared_contact.update!(name: formatted_name)
    end
  end

  def normalized_contact_phone_numbers(contact_payload)
    Array(contact_payload[:phones] || contact_payload['phones']).filter_map do |phone|
      raw_phone = (phone[:phone] || phone['phone']).to_s.gsub(/\D/, '')
      next if raw_phone.blank? || raw_phone == '0'
      next unless raw_phone.match?(/^[1-9]\d{7,14}$/)

      raw_phone = normalised_brazil_mobile_number(raw_phone) if brazil_phone_number?(raw_phone)
      waid = processed_waid(raw_phone) || raw_phone
      "+#{waid}" if waid.present?
    end.uniq
  end

  def contact_name_updatable?(contact, raw_from: nil)
    contact_name_has_lid_suffix?(contact) || contact_name_matches_phone_number?(contact, raw_from) || contact_name_low_quality?(contact)
  end

  def contact_name_matches_phone_number?(contact, raw_from = nil)
    raw_from = raw_from.presence || messages_data&.first&.[](:from).to_s
    raw_from = contact_params[:wa_id].to_s if raw_from.blank? && contact_params.present?
    return false if raw_from.blank? || raw_from.include?('@lid')

    raw_digits = raw_from.gsub(/\D/, '')
    return false if raw_digits.blank?

    phone_number = "+#{raw_digits}"
    formatted_phone_number = TelephoneNumber.parse(phone_number).international_number
    contact_name = contact.name.to_s
    contact_digits = contact_name.gsub(/\D/, '')

    contact_name == phone_number ||
      contact_name == formatted_phone_number ||
      (contact_digits.present? && contact_digits == raw_digits)
  end

  def contact_name_has_lid_suffix?(contact)
    contact.name.to_s.downcase.end_with?('@lid')
  end

  def contact_name_low_quality?(contact)
    contact_name = contact.name.to_s.strip
    return true if contact_name.blank?
    return true if contact_name.length <= 3

    contact_name.match?(/\A[^\p{L}\p{N}]+\z/)
  end
end
