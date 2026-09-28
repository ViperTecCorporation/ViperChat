class Api::V1::Accounts::Google::EmailHistoriesController < Api::V1::Accounts::BaseController
  require_account_feature 'inbox_management', only: [:create, :destroy]
  before_action :set_channel

  def show
    render json: @channel.provider_config.to_h[Google::EmailHistory::KEY] || { status: 'not_started' }
  end

  def create
    Google::EmailHistory.start!(@channel, params[:period])
    show
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    history = @channel.provider_config.to_h[Google::EmailHistory::KEY]
    Google::EmailHistory.update!(@channel, history['id'], 'status' => 'stopped') if history
    show
  end

  private

  def set_channel
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?

    inbox = Current.account.inboxes.find(params[:inbox_id])
    raise ActiveRecord::RecordNotFound unless inbox.channel.is_a?(Channel::Email) && inbox.channel.google?

    @channel = inbox.channel
  end
end
