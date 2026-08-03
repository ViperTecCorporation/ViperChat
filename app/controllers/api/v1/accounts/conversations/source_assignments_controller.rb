class Api::V1::Accounts::Conversations::SourceAssignmentsController < Api::V1::Accounts::BaseController
  def create
    result = Conversations::AssignBySourceService.new(
      account: Current.account,
      inbox_phone_number: params.require(:inbox_phone_number),
      contact_identifier: params.require(:contact_identifier),
      team_name: params.require(:team_name)
    ).perform

    authorize result[:conversation], :show?
    result[:conversation].update!(team: result[:team])

    render json: {
      success: true,
      conversation_id: result[:conversation].display_id,
      inbox_id: result[:inbox].id,
      team_id: result[:team].id,
      team_name: result[:team].name
    }
  end
end
