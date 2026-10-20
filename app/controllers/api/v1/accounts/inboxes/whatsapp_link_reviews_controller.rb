class Api::V1::Accounts::Inboxes::WhatsappLinkReviewsController < Api::V1::Accounts::BaseController
  require_account_feature 'inbox_management'
  before_action :fetch_link

  rescue_from Whatsapp::UnifiedReviewService::Conflict do
    render json: { error: 'review_changed' }, status: :conflict
  end

  rescue_from ArgumentError do
    render json: { error: 'invalid_review_request' }, status: :unprocessable_entity
  end

  def index
    return render json: { items: [], meta: { page: 1, total: 0, total_pages: 0 } } unless @link

    render json: review_service.list(page: params[:page], kind: params[:kind], status: params[:status])
  end

  def recheck
    act('recheck')
  end

  def acknowledge
    act('acknowledge')
  end

  private

  def fetch_link
    inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize inbox, :update?
    @link = WhatsappInboxLink.where(account_id: Current.account.id).covering(inbox.id)
                             .order(enabled: :desc, updated_at: :desc, id: :desc).first
    return unless @link

    authorize @link.primary_inbox, :update?
    authorize @link.secondary_inbox, :update?
  end

  def review_service
    Whatsapp::UnifiedReviewService.new(link: @link, actor: Current.user)
  end

  def act(action)
    raise ActiveRecord::RecordNotFound unless @link
    raise ArgumentError unless params[:version].present? && (params[:version].is_a?(String) || params[:version].is_a?(Integer))

    render json: { item: review_service.act(id: params[:id], action: action, version: params[:version]) }
  end
end

Api::V1::Accounts::Inboxes::WhatsappLinkReviewsController.prepend_mod_with('Api::V1::Accounts::Inboxes::WhatsappLinkReviewsController')
