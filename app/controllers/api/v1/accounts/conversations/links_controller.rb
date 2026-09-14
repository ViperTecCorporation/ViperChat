class Api::V1::Accounts::Conversations::LinksController < Api::V1::Accounts::Conversations::BaseController
  def index
    render json: Conversations::LinksService.new(@conversation).perform(page: params[:page] || 1)
  end
end
