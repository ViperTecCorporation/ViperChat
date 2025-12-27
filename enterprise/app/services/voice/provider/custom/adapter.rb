class Voice::Provider::Custom::Adapter
  pattr_initialize [:channel!]

  def initiate_call(to:, conference_sid: nil, agent_id: nil)
    Rails.logger.info(
      "VOICE_CUSTOM_ADAPTER initiate_call channel_id=#{channel.id} inbox_id=#{channel.inbox_id} to=#{to} agent_id=#{agent_id}"
    )
    { call_sid: SecureRandom.uuid }
  end
end
