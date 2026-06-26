module Enterprise::Api::V1::AccountsSettings
  private

  def settings_params
    permitted_params = super
    return permitted_params unless params.key?(:conversation_required_attributes)

    required_attributes = Array.wrap(params[:conversation_required_attributes])
                               .map { |required_attribute| permitted_required_attribute(required_attribute) }
                               .compact

    permitted_params.merge(conversation_required_attributes: required_attributes)
  end

  def permitted_settings_attributes
    super
  end

  def permitted_required_attribute(required_attribute)
    return required_attribute if required_attribute.is_a?(String)
    return required_attribute.slice('attribute_key', 'inbox_id', 'apply_to_groups') if required_attribute.is_a?(Hash)

    required_attribute.permit(:attribute_key, :inbox_id, :apply_to_groups).to_h if required_attribute.respond_to?(:permit)
  end
end
