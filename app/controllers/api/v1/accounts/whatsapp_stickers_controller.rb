class Api::V1::Accounts::WhatsappStickersController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox, only: [:index, :create]
  before_action :fetch_sticker, only: [:destroy]

  def index
    stickers = @inbox.whatsapp_stickers.includes(:blob)
    recent = stickers.where.not(last_used_at: nil).order(last_used_at: :desc).limit(10)
    Rails.logger.info("[WhatsappStickers] index inbox_id=#{@inbox.id} recent=#{recent.size} total=#{stickers.size}")
    render json: { recent: serialize(recent), all: serialize(stickers.order(created_at: :desc)) }
  end

  def create
    blob = ActiveStorage::Blob.find_signed(create_params[:blob_signed_id])
    sticker = @inbox.whatsapp_stickers.create!(
      account: Current.account,
      blob: blob
    )
    Rails.logger.info("[WhatsappStickers] create inbox_id=#{@inbox.id} sticker_id=#{sticker.id} blob_id=#{blob.id}")
    render json: serialize([sticker]).first
  end

  def destroy
    blob = @sticker.blob
    @sticker.destroy!
    Rails.logger.info("[WhatsappStickers] destroy sticker_id=#{@sticker.id} blob_id=#{blob.id}")
    blob.purge_later if WhatsappSticker.where(blob_id: blob.id).none?
    head :ok
  end

  def bulk_destroy
    stickers = Current.account.whatsapp_stickers.where(id: params[:ids])
    blob_ids = stickers.pluck(:blob_id)
    Rails.logger.info("[WhatsappStickers] bulk_destroy count=#{stickers.size} ids=#{stickers.pluck(:id).join(',')}")
    stickers.destroy_all
    ActiveStorage::Blob.where(id: blob_ids).find_each do |blob|
      blob.purge_later if WhatsappSticker.where(blob_id: blob.id).none?
    end
    head :ok
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(inbox_id_param)
    return if @inbox.whatsapp?

    raise ActiveRecord::RecordNotFound
  end

  def fetch_sticker
    @sticker = Current.account.whatsapp_stickers.find(params[:id])
  end

  def create_params
    params.require(:whatsapp_sticker).permit(:inbox_id, :blob_signed_id)
  end

  def inbox_id_param
    params[:inbox_id] || params.dig(:whatsapp_sticker, :inbox_id)
  end

  def serialize(records)
    records.map do |sticker|
      {
        id: sticker.id,
        inbox_id: sticker.inbox_id,
        file_url: sticker.file_url,
        thumb_url: sticker.thumb_url,
        last_used_at: sticker.last_used_at,
        created_at: sticker.created_at
      }
    end
  end
end
