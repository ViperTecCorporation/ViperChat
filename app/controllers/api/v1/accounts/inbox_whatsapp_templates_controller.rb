class Api::V1::Accounts::InboxWhatsappTemplatesController < Api::V1::Accounts::BaseController
  require_account_feature 'inbox_management'
  before_action :fetch_inbox

  def index
    render json: { templates: @inbox.channel.message_templates || [], last_updated_at: @inbox.channel.message_templates_last_updated }
  end

  def create
    definition = Whatsapp::TemplateDefinition.new(template_params.to_h)
    unless definition.valid?
      return render json: { error: 'validation_failed', errors: definition.errors.map { |e| "#{e.attribute}.#{e.type}" } },
                    status: :unprocessable_entity
    end

    result = Whatsapp::TemplateCreationService.new(channel: @inbox.channel, definition: definition).perform
    status = if result[:error].blank?
               :created
             elsif %w[outcome_unknown name_conflict].include?(result[:error])
               :conflict
             else
               :unprocessable_entity
             end
    render json: result, status: status
  rescue ActionController::ParameterMissing
    render json: { error: 'validation_failed', errors: ['template.required'] }, status: :unprocessable_entity
  end

  def sync
    result = Whatsapp::TemplateSyncService.new(channel: @inbox.channel).perform
    render json: result, status: result[:error] ? :unprocessable_entity : :ok
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize @inbox, :update?
    return if @inbox.channel.is_a?(Channel::Whatsapp) && @inbox.channel.provider == 'whatsapp_cloud'

    render json: { error: 'unsupported_provider' }, status: :bad_request
  end

  def template_params
    params.require(:template).permit(:name, :category, :language, :body, :header, :footer, examples: [], buttons: [:type, :text, :url])
  end
end
