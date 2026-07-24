class Api::V1::Accounts::Conversations::GroupContactsController < Api::V1::Accounts::Conversations::BaseController
  RESULTS_PER_PAGE = 25
  ROLE_ACTIONS = %w[promote demote].freeze
  PARTICIPANT_IDENTIFIER_KEYS = [:wa_id, :phone_number, :phoneNumber, :pn, :jid, :id, :user_id, :lid].freeze
  PARTICIPANT_PAYLOAD_KEYS = [:wa_id, :user_id].freeze
  before_action :ensure_session_group_admin, only: [:create, :destroy, :update]

  def index
    @group_contacts = searchable_group_contacts.includes(:contact).page(params[:page]).per(RESULTS_PER_PAGE)
  end

  def create
    participants = participant_payloads(params[:participants])
    return render json: { error: 'participants are required' }, status: :unprocessable_entity if participants.blank?

    response = @conversation.inbox.channel.provider_service.add_group_participants(
      group_id: @conversation.group_source_id,
      participants: participants
    )
    return render json: response.parsed_response if response.success?

    Rails.logger.warn(
      "[WHATSAPP][GROUP] add participants failed conversation_id=#{@conversation.id} group_source_id=#{@conversation.group_source_id} " \
      "participants=#{participants.inspect} status=#{response.code} response=#{response.parsed_response.inspect}"
    )
    render json: { error: provider_error(response, 'Provider failed to add participants') }, status: provider_failure_status(response)
  end

  def destroy
    participants = participant_identifiers(params[:participants])
    return head :no_content if participants.blank?

    response = remove_provider_participants(participants)
    unless provider_remove_success?(response)
      return render json: { error: provider_error(response, 'Provider failed to remove participants') },
                    status: provider_failure_status(response)
    end

    @conversation.group_contacts.includes(contact: :contact_inboxes).find_each do |group_contact|
      group_contact.destroy! if participants.include?(participant_identifier(group_contact))
    end

    head :no_content
  end

  def update
    action = request.request_parameters['action'].to_s
    return render json: { error: 'action must be promote or demote' }, status: :unprocessable_entity unless ROLE_ACTIONS.include?(action)

    participants = role_participant_payloads(params[:participants])
    return render json: { error: 'participants are required' }, status: :unprocessable_entity if participants.blank?

    eligible, local_failures = eligible_role_participants(participants, action)
    return render_role_response(action, [], local_failures) if eligible.blank?

    response = @conversation.inbox.channel.provider_service.update_group_participant_roles(
      group_id: @conversation.group_source_id,
      action: action,
      participants: eligible
    )
    unless response.success?
      return render json: { error: provider_error(response, 'Provider failed to update participant roles') },
                    status: provider_failure_status(response)
    end

    payload = (response.parsed_response || {}).with_indifferent_access
    successful = Array(payload[action == 'promote' ? :promoted : :demoted])
    update_local_participant_roles(successful, action)
    render_role_response(action, successful, local_failures + Array(payload[:failed]))
  end

  private

  def ensure_session_group_admin
    render json: { error: 'Connected session must be a group admin' }, status: :forbidden unless @conversation.group_session_admin?
  end

  def searchable_group_contacts
    scope = @conversation.group_contacts.joins(:contact)
    query = params[:query].to_s.strip
    return scope if query.blank?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
    scope.where(
      'LOWER(contacts.name) LIKE :pattern OR LOWER(contacts.whatsapp_username) LIKE :pattern OR ' \
      'LOWER(contacts.bsuid) LIKE :pattern OR LOWER(contacts.phone_number) LIKE :pattern OR ' \
      'LOWER(contacts.email) LIKE :pattern OR LOWER(group_contacts.metadata::text) LIKE :pattern',
      pattern: pattern
    )
  end

  def remove_provider_participants(participants)
    return unless @conversation.inbox.channel.provider == 'unoapi'

    @conversation.inbox.channel.provider_service.remove_group_participants(
      group_id: @conversation.group_source_id,
      participants: participants
    )
  end

  def provider_remove_success?(response)
    return true if response.blank?
    return false unless response.success?

    Array(response.parsed_response.try(:[], 'failed')).blank?
  end

  def participant_identifiers(raw_participants)
    Array(raw_participants).filter_map do |participant|
      participant_identifier_from_param(participant)
    end.uniq
  end

  def participant_payloads(raw_participants)
    Array(raw_participants).filter_map do |participant|
      participant_payload_from_param(participant)
    end.uniq
  end

  def role_participant_payloads(raw_participants)
    Array(raw_participants).filter_map do |participant|
      attrs = participant.respond_to?(:to_unsafe_h) ? participant.to_unsafe_h : participant
      next unless attrs.is_a?(Hash)

      attrs = attrs.with_indifferent_access
      user_id = participant_lid_identifier(attrs)
      wa_id = participant_phone_identifier(attrs)
      { 'user_id' => user_id, 'wa_id' => wa_id }.compact.presence
    end.uniq
  end

  def eligible_role_participants(participants, action)
    participants.each_with_object([[], []]) do |participant, (eligible, failures)|
      group_contact = find_group_contact(participant)
      reason = role_change_failure_reason(group_contact, action)
      if reason.present?
        failures << participant.merge('error' => reason)
      else
        eligible << participant
      end
    end
  end

  def role_change_failure_reason(group_contact, action)
    return 'participant_not_found' if group_contact.blank?
    return 'already_admin' if action == 'promote' && group_contact_admin?(group_contact)
    return 'self_demote_confirmation_required' if action == 'demote' && session_group_contact?(group_contact) && !self_demote_confirmed?

    nil
  end

  def self_demote_confirmed?
    ActiveModel::Type::Boolean.new.cast(params[:confirmed_self_demote])
  end

  def group_contact_admin?(group_contact)
    metadata = group_contact.metadata || {}
    ActiveModel::Type::Boolean.new.cast(metadata['is_admin']) ||
      %w[admin superadmin].include?(metadata['role'].to_s.downcase)
  end

  def session_group_contact?(group_contact)
    identifiers_match?(group_contact_identifiers(group_contact), session_identifiers)
  end

  def find_group_contact(participant)
    identifiers = participant.values_at('user_id', 'wa_id').compact
    @conversation.group_contacts.includes(contact: :contact_inboxes).find do |group_contact|
      identifiers_match?(group_contact_identifiers(group_contact), identifiers)
    end
  end

  def group_contact_identifiers(group_contact)
    metadata = group_contact.metadata || {}
    contact_inbox_ids = group_contact.contact.contact_inboxes.filter_map do |contact_inbox|
      contact_inbox.source_id if contact_inbox.inbox_id == @conversation.inbox_id
    end
    [
      metadata['user_id'], metadata['lid'], metadata['wa_id'], metadata['jid'],
      group_contact.contact.bsuid, group_contact.contact.phone_number, *contact_inbox_ids
    ].compact.map(&:to_s)
  end

  def session_identifiers
    channel = @conversation.inbox.channel
    [
      channel.provider_config['business_account_id'],
      channel.provider_config['phone_number_id'],
      channel.phone_number
    ].compact.map(&:to_s)
  end

  def identifiers_match?(left, right)
    left.any? do |left_identifier|
      right.any? do |right_identifier|
        left_identifier == right_identifier ||
          left_identifier.gsub(/\D/, '') == right_identifier.gsub(/\D/, '')
      end
    end
  end

  def update_local_participant_roles(successful_identifiers, action)
    is_admin = action == 'promote'
    Array(successful_identifiers).each do |identifier|
      group_contact = find_group_contact('user_id' => identifier, 'wa_id' => identifier)
      next if group_contact.blank?

      metadata = (group_contact.metadata || {}).merge(
        'is_admin' => is_admin,
        'role' => is_admin ? 'admin' : 'member'
      )
      group_contact.update!(metadata: metadata)
    end
  end

  def render_role_response(action, successful, failures)
    key = action == 'promote' ? :promoted : :demoted
    render json: {
      group_id: @conversation.group_source_id,
      key => successful,
      failed: failures
    }
  end

  def participant_payload_from_param(participant)
    return participant.to_s.presence unless participant.respond_to?(:to_unsafe_h) || participant.is_a?(Hash)

    attrs = participant.respond_to?(:to_unsafe_h) ? participant.to_unsafe_h : participant
    attrs = attrs.with_indifferent_access
    wa_id = participant_phone_identifier(attrs)
    user_id = participant_lid_identifier(attrs)
    payload = PARTICIPANT_PAYLOAD_KEYS.each_with_object({}) do |key, result|
      value = key == :wa_id ? wa_id : user_id
      result[key.to_s] = value if value.present?
    end

    payload.presence
  end

  def participant_phone_identifier(attrs)
    [attrs[:wa_id], attrs[:phone_number], attrs[:phoneNumber], attrs[:pn], attrs[:jid], attrs[:id]].filter_map do |value|
      next if value.to_s.strip.end_with?('@lid')

      digits = value.to_s.gsub(/\D/, '')
      digits if digits.length >= 8
    end.first
  end

  def participant_lid_identifier(attrs)
    [attrs[:user_id], attrs[:lid], attrs[:wa_id], attrs[:jid], attrs[:id]].filter_map do |value|
      value = value.to_s.strip
      value if value.end_with?('@lid')
    end.first
  end

  def participant_identifier_from_param(participant)
    return participant.to_s.presence unless participant.respond_to?(:to_unsafe_h) || participant.is_a?(Hash)

    attrs = participant.respond_to?(:to_unsafe_h) ? participant.to_unsafe_h : participant
    attrs = attrs.with_indifferent_access
    PARTICIPANT_IDENTIFIER_KEYS.filter_map { |key| attrs[key].presence }.first
  end

  def provider_error(response, fallback)
    payload = response.parsed_response
    payload = payload.with_indifferent_access if payload.respond_to?(:with_indifferent_access)
    payload.try(:[], :error) || fallback
  end

  def provider_failure_status(response)
    status = response.code.to_i
    status.between?(400, 599) ? status : :unprocessable_entity
  end

  def participant_identifier(group_contact)
    metadata = group_contact.metadata || {}
    metadata_identifier = PARTICIPANT_IDENTIFIER_KEYS.filter_map { |key| metadata[key.to_s].presence }.first
    contact_inbox_source_id = group_contact.contact.contact_inboxes.find do |contact_inbox|
      contact_inbox.inbox_id == @conversation.inbox_id
    end&.source_id

    [metadata_identifier, contact_inbox_source_id, group_contact.contact.phone_number, group_contact.contact.bsuid,
     group_contact.contact.email].find(&:present?)
  end
  helper_method :participant_identifier, :session_group_contact?
end
