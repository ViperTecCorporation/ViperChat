class SuperAdmin::NativeSessionsController < ApplicationController
  def show
    super_admin = SuperAdmin.from_email(params[:email])
    return head :unauthorized unless valid_token?(super_admin)

    super_admin.invalidate_sso_auth_token(params[:sso_auth_token])
    sign_in(:super_admin, super_admin)
    redirect_to super_admin_root_path
  end

  private

  def valid_token?(super_admin)
    super_admin.present? &&
      params[:sso_auth_token].present? &&
      super_admin.valid_sso_auth_token?(params[:sso_auth_token])
  end
end
