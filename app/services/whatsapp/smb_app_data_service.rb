# The Meta endpoint is one-shot per onboarding, without a documented idempotency key.
# Reserve in PostgreSQL BEFORE dispatch. Never automatically repeat an uncertain POST.
class Whatsapp::SmbAppDataService
  class PreparationError < StandardError; end

  def initialize(channel:)
    @channel = channel
  end

  def perform
    return unless enabled?
    return if terminal_requests?

    prove_coexistence!
    @client = Whatsapp::SmbAppDataClient.new(@channel)
    return unless prepare_webhooks!

    WhatsappSmbSyncRequest::TYPES.all? { |type| request_once(type) }
  end

  private

  def enabled?
    ENV['WHATSAPP_SMB_SYNC_ENABLED'] == 'true' && @channel.provider == 'whatsapp_cloud' &&
      @channel.account.active? && !@channel.reauthorization_required? && @channel.provider_config['ignore_history_messages'] == false
  end

  def terminal_requests?
    requests = WhatsappSmbSyncRequest.where(phone_number_id: @channel.provider_config['phone_number_id'])
    return true if requests.exists?(['channel_id != :channel OR account_id != :account OR waba_id != :waba',
                                     { channel: @channel.id, account: @channel.account_id,
                                       waba: @channel.provider_config['business_account_id'] }])

    requests.exists?(state: %w[dispatched rejected uncertain]) || requests.where(state: 'accepted').count == 2
  end

  def prove_coexistence!
    @phone_id = @channel.provider_config['phone_number_id']
    @waba_id = @channel.provider_config['business_account_id']
    raise PreparationError, 'configuration_missing' if @phone_id.blank? || @waba_id.blank?

    data = Whatsapp::ManagementApiClient.new(@channel).get(@phone_id, fields: 'is_on_biz_app,platform_type')
    raise PreparationError, 'not_coexistence' unless data['is_on_biz_app'] == true && data['platform_type'] == 'CLOUD_API'
  end

  def prepare_webhooks!
    snapshot = webhook_snapshot
    return false unless snapshot

    Whatsapp::WebhookSetupService.new(snapshot).register_callback
    true
  rescue StandardError
    # The existing setup client can raise a raw provider body. Do not log or expose it here.
    raise PreparationError, 'webhook_setup_failed', cause: nil
  end

  def webhook_snapshot
    @channel.with_lock do
      next unless current_context?

      fields = Array(@channel.provider_config['webhook_fields']) | %w[history smb_app_state_sync smb_message_echoes]
      @channel.update_columns( # rubocop:disable Rails/SkipsModelValidations
        provider_config: @channel.provider_config.merge('webhook_fields' => fields), updated_at: Time.current
      )
      # Never retarget the external callback if the live channel changes after
      # releasing this lock. This separate instance retains the proved identity.
      @channel.class.find(@channel.id)
    end
  end

  def request_once(type)
    row = reserve_request(type)
    return false unless row
    return true if row.state == 'accepted'

    dispatch(row)
  end

  def reserve_request(type)
    row = WhatsappSmbSyncRequest.create_or_find_by!(phone_number_id: @phone_id, sync_type: type) do |request|
      request.assign_attributes(account: @channel.account, channel: @channel, waba_id: @waba_id,
                                history_max_age_days: @channel.provider_config.fetch('history_max_age_days', 7).to_i.clamp(1, 3650))
    end
    return unless row.channel_id == @channel.id && row.account_id == @channel.account_id && row.waba_id == @waba_id

    row.with_lock do
      next row if row.state == 'accepted'
      next unless row.state == 'prepared' && current_context?

      row.update!(state: 'dispatched', dispatched_at: Time.current)
      row
    end
  end

  def current_context?
    # Stop if the operator disabled import or changed credentials while preparing.
    @channel.reload
    enabled? && @channel.provider_config['phone_number_id'] == @phone_id && @channel.provider_config['business_account_id'] == @waba_id
  end

  def dispatch(row)
    request_id = @client.request(row.sync_type)
    row.update!(state: 'accepted', request_id: request_id, reason: nil)
    true
  rescue Whatsapp::SmbAppDataClient::Error => e
    row.update!(state: e.ambiguous? ? 'uncertain' : 'rejected', reason: e.reason)
    false
  end
end
