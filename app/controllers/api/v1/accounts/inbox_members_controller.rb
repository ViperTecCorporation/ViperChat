class Api::V1::Accounts::InboxMembersController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox
  before_action :current_agents_ids, only: [:create, :update]

  def show
    authorize @inbox, :show?
    fetch_updated_agents
  end

  def create
    authorize @inbox, :create?
    ActiveRecord::Base.transaction do
      @inbox.add_members(agents_to_be_added_ids)
    end
    fetch_updated_agents
  end

  def update
    authorize @inbox, :update?
    Rails.logger.info(
      "INBOX_MEMBERS_UPDATE " \
      "account_id=#{Current.account.id} " \
      "inbox_id=#{@inbox.id} " \
      "user_ids_present=#{params[:user_ids].present?} " \
      "member_attributes_count=#{member_attributes.length}"
    )
    ActiveRecord::Base.transaction do
      update_agents_list if params[:user_ids].present?
      update_member_credentials if member_attributes.present?
    end
    fetch_updated_agents
  end

  def destroy
    authorize @inbox, :destroy?
    ActiveRecord::Base.transaction do
      @inbox.remove_members(params[:user_ids])
    end
    head :ok
  end

  private

  def fetch_updated_agents
    @inbox_members = @inbox.inbox_members.includes(user: { avatar_attachment: :blob })
  end

  def update_agents_list
    # get all the user_ids which the inbox currently has as members.
    # get the list of  user_ids from params
    # the missing ones are the agents which are to be deleted from the inbox
    # the new ones are the agents which are to be added to the inbox
    ActiveRecord::Base.transaction do
      Rails.logger.info(
        "INBOX_MEMBERS_UPDATE_LIST " \
        "account_id=#{Current.account.id} " \
        "inbox_id=#{@inbox.id} " \
        "add_count=#{agents_to_be_added_ids.length} " \
        "remove_count=#{agents_to_be_removed_ids.length}"
      )
      @inbox.add_members(agents_to_be_added_ids)
      @inbox.remove_members(agents_to_be_removed_ids)
    end
  end

  def agents_to_be_added_ids
    return [] if params[:user_ids].blank?

    params[:user_ids] - @current_agents_ids
  end

  def agents_to_be_removed_ids
    return [] if params[:user_ids].blank?

    @current_agents_ids - params[:user_ids]
  end

  def current_agents_ids
    @current_agents_ids = @inbox.members.pluck(:id)
  end

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end

  def update_member_credentials
    member_attributes.each do |attrs|
      user_id = attrs[:user_id]
      next if user_id.blank?

      inbox_member = @inbox.inbox_members.find_by(user_id: user_id)
      next unless inbox_member

      updates = {}
      if attrs.key?(:webrtc_username) || attrs.key?('webrtc_username')
        updates[:webrtc_username] = attrs[:webrtc_username]
      end
      updates[:webrtc_jwt] = attrs[:webrtc_jwt] if attrs[:webrtc_jwt].present?
      updates[:webrtc_password] = attrs[:webrtc_password] if attrs[:webrtc_password].present?

      Rails.logger.info(
        "INBOX_MEMBER_CREDENTIALS_UPDATE " \
        "account_id=#{Current.account.id} " \
        "inbox_id=#{@inbox.id} " \
        "user_id=#{user_id} " \
        "username_set=#{updates.key?(:webrtc_username)} " \
        "jwt_set=#{updates.key?(:webrtc_jwt)} " \
        "password_set=#{updates.key?(:webrtc_password)}"
      )
      inbox_member.update!(updates) if updates.present?
    end
  end

  def member_attributes
    @member_attributes ||= params.permit(member_attributes: [:user_id, :webrtc_jwt, :webrtc_username, :webrtc_password])
                                 .fetch(:member_attributes, [])
  end
end
