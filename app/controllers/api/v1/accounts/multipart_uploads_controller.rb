class Api::V1::Accounts::MultipartUploadsController < Api::V1::Accounts::BaseController
  before_action :upload, except: [:index, :create]
  rescue_from Uploads::MultipartService::InvalidUpload, with: :invalid_upload

  def index
    render json: { supported: Uploads::MultipartService.supported? }
  end

  def create
    authorize_conversation(params[:conversation_id])
    attributes = params.require(:blob).permit(:filename, :byte_size, :checksum, :content_type).to_h.symbolize_keys
    service = Uploads::MultipartService.start!(attributes, {
                                                 'account_id' => Current.account.id, 'user_id' => Current.user.id,
                                                 'conversation_id' => params[:conversation_id].presence,
                                                 'direct' => direct_uploads_enabled?
                                               })
    render json: { token: service.blob.signed_id(purpose: Uploads::MultipartService::PURPOSE),
                   part_size: Uploads::MultipartService::PART_SIZE, direct: service.session['direct'] }
  end

  def part
    number = params.require(:part_number).to_i
    checksum = params.require(:checksum)
    if request.put?
      raise Uploads::MultipartService::InvalidUpload, 'Use signed part upload' if @upload.session['direct']

      @upload.upload_part(number, params[:file], checksum)
      head :no_content
    else
      raise Uploads::MultipartService::InvalidUpload, 'Direct uploads are disabled' unless @upload.session['direct'] && direct_uploads_enabled?

      render json: { url: @upload.part_url(number, checksum), headers: { 'Content-MD5' => checksum } }
    end
  end

  def complete
    blob = @upload.complete!
    render json: blob.as_json(root: false, methods: :signed_id).except('metadata', 'key')
  end

  def destroy
    @upload.abort!
    head :no_content
  end

  private

  def upload
    blob = ActiveStorage::Blob.find_signed!(params[:id], purpose: Uploads::MultipartService::PURPOSE)
    @upload = Uploads::MultipartService.new(blob)
    raise ActiveRecord::RecordNotFound unless @upload.session['account_id'] == Current.account.id && @upload.session['user_id'] == Current.user.id

    authorize_conversation(@upload.session['conversation_id'])
  end

  def authorize_conversation(id)
    return if id.blank?

    authorize Current.account.conversations.find_by!(display_id: id), :show?
  end

  def direct_uploads_enabled?
    ActiveModel::Type::Boolean.new.cast(GlobalConfigService.load('DIRECT_UPLOADS_ENABLED', 'false'))
  end

  def invalid_upload(error)
    render json: { error: error.message }, status: :unprocessable_entity
  end
end
