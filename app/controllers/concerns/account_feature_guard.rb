module AccountFeatureGuard
  extend ActiveSupport::Concern

  class_methods do
    def require_account_feature(feature, **)
      before_action(**) do
        current_account unless Current.account
        next if performed?

        raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?(feature)
      end
    end
  end
end
