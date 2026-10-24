# Durable idempotency for the local text outbox. The conversation lock serializes
# retries across tabs, Rails workers and lost HTTP responses without a Redis TTL.
class Messages::IdempotentCreateService
  def initialize(user:, conversation:, params:)
    @user = user
    @conversation = conversation
    @params = params
  end

  def perform
    validate_request!
    key = @params[:client_message_id].to_s
    data = @params.permit(:content, :private, :delivery_destination, :whatsapp_transport, content_attributes: [:in_reply_to]).to_h
    data['private'] = ActiveModel::Type::Boolean.new.cast(data['private']) || false
    digest = Digest::SHA256.hexdigest(data.sort.to_h.to_json)
    @conversation.with_lock do
      existing = @conversation.messages.where(sender: @user).with_content_attribute('client_message_id', key).first
      if existing
        raise ArgumentError, 'Client message ID reused with different content' if existing.content_attributes['client_message_digest'] != digest

        existing.echo_id = @params[:echo_id]
        next existing
      end

      build_message(data, key, digest)
    end
  end

  private

  def validate_request!
    key = @params[:client_message_id].to_s
    raise ArgumentError, 'Invalid client message ID' unless key.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i)
    raise ArgumentError, 'Text outbox requires a user' unless @user.is_a?(User)
    if @params[:attachments].present? || @params[:template_params].present?
      raise ArgumentError, 'Text outbox does not accept attachments or templates'
    end
    return if [nil, 'text'].include?(@params[:content_type]) && [nil, 'outgoing'].include?(@params[:message_type])

    raise ArgumentError, 'Text outbox only accepts outgoing text'
  end

  def build_message(data, key, digest)
    data['content_attributes'] = (data['content_attributes'] || {}).merge(
      'client_message_id' => key, 'client_message_digest' => digest
    )
    build_params = ActionController::Parameters.new(data.merge('echo_id' => @params[:echo_id], 'content_type' => 'text', 'action' => 'create'))
    Messages::MessageBuilder.new(@user, @conversation, build_params).perform
  end
end
