require 'digest'

class Whatsapp::Unoapi::ContactSync::ContactExporter
  EXPORT_ATTRIBUTE = 'unoapi_contact_export'.freeze

  def initialize(channel:, contact:, client:)
    @channel = channel
    @contact = contact
    @client = client
  end

  def perform
    return :skipped if links.empty? || imported_from_unoapi?

    payload = export_payload
    return :skipped if payload.blank? || already_attempted?(payload)

    payload = verified_payload(payload)
    return :skipped if already_attempted?(payload)

    response = @client.import_contact(payload)
    remote_contact = response.fetch('contact')
    mark_attempt(payload, status: 'exported', remote_contact: remote_contact)
    :processed
  rescue Whatsapp::Unoapi::ContactSync::Client::PermanentError, KeyError => e
    mark_attempt(payload, status: 'failed', error: e.message) if payload.present?
    Rails.logger.error(
      "[UNOAPI CONTACT EXPORT] channel_id=#{@channel.id} contact_id=#{@contact.id} " \
      "error=#{e.class}: #{e.message}"
    )
    :failed
  end

  private

  def links
    @links ||= @channel.inbox.contact_inboxes.where(contact: @contact).to_a
  end

  def imported_from_unoapi?
    links.any? { |link| link.additional_attributes.key?('unoapi_last_updated_ms') }
  end

  def already_attempted?(payload)
    signature = export_signature(payload)
    links.any? { |link| link.additional_attributes.dig(EXPORT_ATTRIBUTE, 'signature') == signature }
  end

  def export_payload
    phone_number = @contact.phone_number.to_s.gsub(/\D/, '')
    return unless phone_number.match?(/\A[1-9]\d{6,14}\z/)

    user_id = lid
    full_name = export_name(phone_number, user_id).first(256)
    {
      phone_number: phone_number,
      full_name: full_name,
      first_name: full_name.split.first.first(128),
      user_id: user_id,
      username: @contact.whatsapp_username.to_s.strip.delete_prefix('@').first(64).presence
    }.compact
  end

  def verified_payload(payload)
    verification = @client.verify_contact(payload[:phone_number]).with_indifferent_access
    verified_lid = verification[:user_id].to_s.strip
    unless verification[:status] == 'valid' && verified_lid.match?(/\A\d+@lid\z/)
      raise Whatsapp::Unoapi::ContactSync::Client::PermanentError, 'UnoAPI could not validate the contact LID'
    end

    payload.merge(user_id: verified_lid)
  end

  def lid
    candidates = [@contact.bsuid, *links.map(&:source_id)]
    candidates.find { |value| value.to_s.match?(/\A\d+@lid\z/) }
  end

  def export_name(phone_number, user_id)
    name = @contact.name.to_s.strip
    return phone_number if name.blank? || name.casecmp?(user_id.to_s) || name.match?(/@\S+\z/i)

    name
  end

  def export_signature(payload)
    Digest::SHA256.hexdigest([payload[:phone_number], payload[:user_id]].compact.join('|'))
  end

  def mark_attempt(payload, status:, remote_contact: nil, error: nil)
    attributes = {
      'signature' => export_signature(payload),
      'status' => status,
      'attempted_at' => Time.current.iso8601(3),
      'phone_number' => remote_contact&.fetch('phone_number', nil) || payload[:phone_number],
      'user_id' => remote_contact&.fetch('user_id', nil) || payload[:user_id],
      'error' => error
    }.compact

    ContactInbox.transaction do
      links.each do |link|
        link.update!(additional_attributes: link.additional_attributes.merge(EXPORT_ATTRIBUTE => attributes))
      end
    end
  end
end
