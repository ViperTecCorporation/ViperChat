class Voip::CreateCallService
  def initialize(binding:, attributes:)
    @binding = binding
    @attributes = attributes.to_h.symbolize_keys
  end

  def perform
    @binding.account_user.with_lock do
      call = @binding.voip_calls.find_by(client_call_id: @attributes.fetch(:client_call_id)) || provider_projection || create_call
      raise ArgumentError, 'voip_call_identity_conflict' unless @attributes.all? { |key, value| call.public_send(key) == value }

      call
    end
  end

  private

  def provider_projection
    return if @attributes[:sip_call_id].blank?

    matches = @binding.voip_calls.where(sip_call_id: @attributes[:sip_call_id], origin: 'provider_authoritative')
    return unless matches.count == 1

    call = matches.first
    return unless call.client_call_id.start_with?('provider:')

    # Exact SIP dialog + same binding, never phone/text/time similarity. Keep the persisted primary key/history.
    call.update!(@attributes)
    call
  end

  def create_call
    raise ArgumentError, 'voip_call_in_progress' if VoipAgentExtension.busy?(@binding.account_user)

    @binding.voip_calls.create!(@attributes.merge(account_id: @binding.account_user.account_id,
                                                  started_at: Time.current, last_observed_at: Time.current))
  end
end
