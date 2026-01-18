class Api::V1::Accounts::CampaignsController < Api::V1::Accounts::BaseController
  before_action :campaign, except: [:index, :create]
  before_action :check_authorization

  def index
    @campaigns = Current.account.campaigns.limit(200).order(created_at: :desc)
  end

  def show; end

  def create
    media_blob_signed_id = params.dig(:campaign, :media_blob_signed_id) || params[:media_blob_signed_id]
    @campaign = Current.account.campaigns.create!(campaign_params)
    attach_media_blob(@campaign, media_blob_signed_id)
  end

  def update
    @campaign.update!(campaign_params)
  end

  def destroy
    @campaign.destroy!
    head :ok
  end

  def duplicate
    original_campaign = @campaign
    @campaign = Current.account.campaigns.create!(duplicate_campaign_params)
    attach_duplicate_media(original_campaign)
    render :create
  end

  private

  def campaign
    @campaign ||= Current.account.campaigns.find_by(display_id: params[:id])
  end

  def campaign_params
    fields = [:title, :description, :message, :enabled, :trigger_only_during_business_hours, :inbox_id, :sender_id, :scheduled_at]
    fields << { trigger_rules: {} }
    fields << { template_params: {} }
    inbox_id = params[:inbox_id] || params.dig(:campaign, :inbox_id)
    fields << if Inbox.find_by(id: inbox_id)&.channel.try(:provider) == 'unoapi'
                { audience: [:type, :id, :name, :phone_number, :identifier, :due_at, :value, :scheduled_at, :email, :wait_for_seconds] }
              else
                { audience: [:type, :id] }
              end
    fields << :media
    permitted = params.require(:campaign).permit(fields)
    [:audience, :template_params, :trigger_rules].each do |key|
      next unless permitted[key].is_a?(String)

      begin
        permitted[key] = JSON.parse(permitted[key])
      rescue JSON::ParserError
        # keep original string
      end
    end
    permitted
  end

  def duplicate_campaign_params
    base = @campaign.attributes.slice(
      'title',
      'description',
      'message',
      'enabled',
      'trigger_only_during_business_hours',
      'inbox_id',
      'sender_id',
      'scheduled_at',
      'campaign_type'
    )
    base['template_params'] = @campaign.template_params
    base['trigger_rules'] = @campaign.trigger_rules
    base['audience'] = normalize_audience_for_duplicate(@campaign.audience)
    base
  end

  def normalize_audience_for_duplicate(audience)
    return [] if audience.blank?

    audience.map do |entry|
      entry.except('status', 'audience_id')
    end
  end

  def attach_duplicate_media(original_campaign)
    return unless original_campaign.media&.attached?
    return if @campaign.media.attached?

    @campaign.media.attach(original_campaign.media.blob)
  end

  def attach_media_blob(campaign, signed_id)
    return if signed_id.blank?

    campaign.media.attach(signed_id)
  end
end
