class Api::V1::Accounts::Voip::DirectoryController < Api::V1::Accounts::Voip::BaseController
  def index
    render json: directory_resolver(authorized_service!).directory(
      kind: params[:kind].presence || 'contacts', search: params[:search].to_s.strip, page: [params[:page].to_i, 1].max
    )
  end

  def identity
    render json: { identity: directory_resolver(authorized_service!).identity(params[:address]) }
  end
end
