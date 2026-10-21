class Voip::CreateCallService
  def initialize(binding:, attributes:)
    @binding = binding
    @attributes = attributes.to_h.symbolize_keys
  end

  def perform
    @binding.account_user.with_lock do
      call = @binding.voip_calls.find_by(client_call_id: @attributes.fetch(:client_call_id)) || create_call
      raise ArgumentError, 'voip_call_identity_conflict' unless @attributes.all? { |key, value| call.public_send(key) == value }

      call
    end
  end

  private

  def create_call
    raise ArgumentError, 'voip_call_in_progress' if VoipAgentExtension.busy?(@binding.account_user)

    @binding.voip_calls.create!(@attributes.merge(account_id: @binding.account_user.account_id,
                                                  started_at: Time.current, last_observed_at: Time.current))
  end
end
