# Explicit, bounded refresh for the administration screen. Never follows a URL supplied by Graph.
class Whatsapp::TemplateSyncService
  def initialize(channel:)
    @channel = channel
  end

  def perform
    config = @channel.provider_config
    @waba_id = config['business_account_id'].to_s
    return { error: 'configuration_missing' } unless @waba_id.match?(/\A\d+\z/) && config['api_key'].present?

    @client = Whatsapp::TemplateApiClient.new(waba_id: @waba_id, token: config['api_key'])
    @started_at = Time.current

    result = fetch_templates
    return result if result[:error]

    @channel.with_lock do
      next { error: 'configuration_missing' } unless @channel.provider_config['business_account_id'].to_s == @waba_id

      result[:templates] = preserve_concurrent_creations(result[:templates])
      @channel.update_columns(message_templates: result[:templates], message_templates_last_updated: Time.current) # rubocop:disable Rails/SkipsModelValidations
      result.merge(last_updated_at: @channel.message_templates_last_updated)
    end
  end

  private

  def fetch_templates
    templates = []
    cursor = nil
    20.times do
      data = @client.list(cursor)
      return data if data[:error]
      return { error: 'temporarily_unavailable' } unless valid_page?(data)

      templates.concat(data['data'])
      return { templates: templates } if data.dig('paging', 'next').blank?

      next_cursor = data.dig('paging', 'cursors', 'after')
      return { error: 'temporarily_unavailable' } if next_cursor.blank? || next_cursor == cursor

      cursor = next_cursor
    end
    { error: 'temporarily_unavailable' }
  end

  def valid_page?(data)
    data['data'].is_a?(Array) && data['data'].all?(Hash) && (data['paging'].nil? || data['paging'].is_a?(Hash))
  end

  def preserve_concurrent_creations(templates)
    requests = WhatsappTemplateRequest.where(account_id: @channel.account_id, waba_id: @waba_id, state: 'accepted')
                                      .where(updated_at: @started_at..)
    requests.each do |request|
      template = request.result['template']
      next if templates.any? { |t| t['name'] == request.name && t['language'] == request.language }

      templates << template if template
    end
    templates
  end
end
