module Enterprise::Concerns::CustomAttributeDefinition
  extend ActiveSupport::Concern

  included do
    after_destroy :cleanup_conversation_required_attributes
  end

  private

  def cleanup_conversation_required_attributes
    return unless conversation_attribute? && account.conversation_required_attributes.present?

    updated_attributes = account.conversation_required_attributes.reject do |required_attribute|
      next true if required_attribute == attribute_key
      next false unless required_attribute.is_a?(Hash)

      required_attribute['attribute_key'] == attribute_key || required_attribute[:attribute_key] == attribute_key
    end
    return if updated_attributes == account.conversation_required_attributes

    account.conversation_required_attributes = updated_attributes
    account.save!
  end
end
