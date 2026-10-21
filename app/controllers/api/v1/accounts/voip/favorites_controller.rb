class Api::V1::Accounts::Voip::FavoritesController < Api::V1::Accounts::Voip::BaseController
  def index
    rows = favorites.includes(:voip_service).order(:name).to_a
    identities = remote_identities(rows)
    render json: rows.map { |row| favorite_payload(row, identities.dig(row.voip_service_id, row.address)) }
  end

  def create
    service = authorized_service!
    favorite = favorites.find_or_initialize_by(voip_service: service, address: params.require(:favorite).fetch(:address))
    favorite.assign_attributes(params.require(:favorite).permit(:name))
    favorite.save!
    render json: favorite_payload(favorite, directory_resolver(service).identity(favorite.address)), status: :created
  end

  def destroy
    favorites.find(params[:id]).destroy!
    head :no_content
  end

  private

  def favorite_payload(favorite, identity)
    favorite.slice(:id, :voip_service_id, :name, :address).merge(remote_identity: identity)
  end

  def favorites
    VoipFavorite.where(account_user: Current.account_user)
  end
end
