class Whatsapp::TemplateCreationService
  def initialize(channel:, definition:)
    @channel = channel
    @payload = definition.payload
  end

  def perform
    config = @channel.provider_config
    return { error: 'configuration_missing' } unless config['business_account_id'].to_s.match?(/\A\d+\z/) && config['api_key'].present?

    # Journal before I/O; never hold a database transaction during a Graph request.
    @waba_id = config['business_account_id'].to_s
    @client = Whatsapp::TemplateApiClient.new(waba_id: @waba_id, token: config['api_key'])
    @fingerprint = Digest::SHA256.hexdigest(JSON.generate(@payload))
    return @existing_result unless reserve_request

    result = submit
    @request.update!(state: result[:error] ? failure_state(result[:error]) : 'accepted',
                     provider_template_id: result.dig(:template, 'id'), result: result)
    cache_template(result[:template]) if result[:template]
    result
  end

  private

  def reserve_request
    @request = WhatsappTemplateRequest.create_or_find_by!(account_id: @channel.account_id, waba_id: @waba_id,
                                                          name: @payload['name'], language: @payload['language']) do |record|
      record.channel = @channel
      record.fingerprint = @fingerprint
    end
    return true if @request.previously_new_record?

    @request.with_lock do
      if @request.state == 'rejected'
        @request.update!(state: 'dispatched', fingerprint: @fingerprint, result: {})
        next true
      end
      @existing_result = replay_result
      false
    end
  end

  def replay_result
    return { error: 'name_conflict' } unless @request.fingerprint == @fingerprint
    return { template: @request.result['template'] } if @request.state == 'accepted'

    recover_synced_template
  end

  def recover_synced_template
    # A later explicit sync may already have recovered an accepted, timed-out creation.
    template = Array(@channel.reload.message_templates).find { |t| t['name'] == @payload['name'] && t['language'] == @payload['language'] }
    return { error: 'outcome_unknown' } unless template && template['id'].present? && matching_components?(template)

    @request.update!(state: 'accepted', provider_template_id: template['id'], result: { template: template })
    { template: template }
  end

  def matching_components?(template)
    comparable = ->(components) { components.map { |component| component.except('example') } }
    comparable.call(template.fetch('components', [])) == comparable.call(@payload['components'])
  end

  def submit
    body = @client.create(@payload)
    return body if body[:error]
    return { error: 'outcome_unknown' } unless body['id'].to_s.match?(/\A\d+\z/)

    { template: @payload.merge('id' => body['id'].to_s, 'status' => body['status'].presence || 'PENDING',
                               'category' => body['category'].presence || @payload['category']) }
  end

  def failure_state(reason)
    reason == 'outcome_unknown' ? 'uncertain' : 'rejected'
  end

  def cache_template(template)
    @channel.with_lock do
      next unless @channel.provider_config['business_account_id'].to_s == @waba_id

      templates = Array(@channel.message_templates).reject { |t| t['name'] == template['name'] && t['language'] == template['language'] }
      @channel.update_columns(message_templates: templates + [template]) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
