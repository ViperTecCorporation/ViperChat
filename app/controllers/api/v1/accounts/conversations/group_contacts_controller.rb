class Api::V1::Accounts::Conversations::GroupContactsController < Api::V1::Accounts::Conversations::BaseController
  RESULTS_PER_PAGE = 25

  def index
    @group_contacts = @conversation.group_contacts.includes(:contact).page(params[:page]).per(RESULTS_PER_PAGE)
  end
end
