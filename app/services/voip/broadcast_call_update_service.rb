class Voip::BroadcastCallUpdateService
  def initialize(external:)
    @external = external
    @service = external.voip_service
  end

  def perform
    members = @service.account.account_users.includes(:user).select do |membership|
      @service.available_to?(membership) && (membership.administrator? || @service.voip_agent_extensions.exists?(account_user: membership))
    end
    tokens = members.map { |membership| membership.user.pubsub_token }
    ActionCableBroadcastJob.perform_later(tokens, 'voip.call.updated',
                                          { account_id: @service.account_id, service_id: @service.id, external_call_id: @external.id,
                                            revision: @external.revision })
  end
end
