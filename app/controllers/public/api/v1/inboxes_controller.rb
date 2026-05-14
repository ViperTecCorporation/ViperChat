class Public::Api::V1::InboxesController < PublicController
  before_action :set_inbox_channel
  before_action :set_contact_inbox
  before_action :set_conversation

  def show
    @inbox_channel = ::Channel::Api.find_by!(identifier: params[:id])
  end

  private

  def set_inbox_channel
    return if params[:inbox_id].blank?

    @inbox_channel = ::Channel::Api.find_by!(identifier: params[:inbox_id])
  end

  def set_contact_inbox
    return if params[:contact_id].blank?

    @contact_inbox = @inbox_channel.inbox.contact_inboxes.find_by(source_id: params[:contact_id])
    Rails.logger.info(
      "[Public::Api::V1::InboxesController] set_contact_inbox " \
      "inbox_identifier=#{@inbox_channel.identifier} contact_id_param=#{params[:contact_id]} " \
      "found_by_source_id=#{@contact_inbox.present?}"
    )
    return if @contact_inbox

    contact = find_contact_by_identifier_or_phone
    Rails.logger.info(
      "[Public::Api::V1::InboxesController] set_contact_inbox fallback " \
      "contact_found=#{contact.present?} contact_id=#{contact&.id} " \
      "identifier=#{contact&.identifier} phone=#{contact&.phone_number}"
    )
    return unless contact

    @contact_inbox = @inbox_channel.inbox.contact_inboxes.find_by(contact_id: contact.id)
    Rails.logger.info(
      "[Public::Api::V1::InboxesController] set_contact_inbox fallback " \
      "contact_inbox_found=#{@contact_inbox.present?} contact_inbox_id=#{@contact_inbox&.id} " \
      "source_id=#{@contact_inbox&.source_id}"
    )
    raise ActiveRecord::RecordNotFound unless @contact_inbox
  end

  def set_conversation
    return if params[:conversation_id].blank?

    @conversation = if @contact_inbox.hmac_verified?
                      @contact_inbox.contact.conversations.find_by!(display_id: params[:conversation_id])
                    else
                      @contact_inbox.conversations.find_by!(display_id: params[:conversation_id])
                    end
    Rails.logger.info(
      "[Public::Api::V1::InboxesController] set_conversation " \
      "conversation_id_param=#{params[:conversation_id]} found_id=#{@conversation&.id} " \
      "display_id=#{@conversation&.display_id}"
    )
  end

  def find_contact_by_identifier_or_phone
    contact_id = params[:contact_id].to_s
    account = @inbox_channel.inbox.account

    contact = account.contacts.find_by(identifier: contact_id)
    return contact if contact

    normalized_phone = normalize_phone_number(contact_id)
    return if normalized_phone.blank?

    account.contacts.find_by(phone_number: normalized_phone)
  end

  def normalize_phone_number(raw)
    digits = raw.gsub(/\D/, '')
    return if digits.blank?

    if digits.start_with?('55')
      return "+#{digits}" if digits.length.between?(12, 13)
    elsif digits.length == 10
      return "+55#{digits[0, 2]}9#{digits[2, 8]}"
    elsif digits.length == 11
      return "+55#{digits}"
    end

    nil
  end
end
