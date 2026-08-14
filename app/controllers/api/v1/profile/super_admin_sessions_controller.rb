class Api::V1::Profile::SuperAdminSessionsController < Api::BaseController
  def create
    return render json: { error: 'Super Admin access required' }, status: :forbidden unless Current.user.is_a?(SuperAdmin)

    render json: {
      url: super_admin_native_session_url(
        email: Current.user.email,
        sso_auth_token: Current.user.generate_sso_auth_token
      )
    }
  end
end
