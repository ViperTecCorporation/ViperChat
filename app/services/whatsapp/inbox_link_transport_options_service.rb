class Whatsapp::InboxLinkTransportOptionsService
  def initialize(link:, conversation:)
    @link = link
    @conversation = conversation
  end

  def perform
    return unless eligible? && authorized_primary?

    {
      link_id: @link.id, primary_inbox_id: @link.primary_inbox_id, default_provider: @link.default_provider,
      transports: WhatsappInboxLink::PROVIDERS.map do |provider|
        {
          provider: provider, label: provider == 'unoapi' ? 'ViperConnect' : 'Meta', inbox_id: @link.inbox_for(provider).id,
          can_reply: provider == 'unoapi' || meta_can_reply?,
          capabilities: Whatsapp::UnifiedTransportService.capabilities(provider)
        }
      end
    }
  end

  private

  def eligible?
    @link.enabled? && @link.activated_at && @link.covers?(@conversation.inbox) &&
      !@conversation.group? && @conversation.account_id == @link.account_id
  end

  def authorized_primary?
    return false unless Current.user.is_a?(User) && Current.account&.id == @link.account_id

    membership = Current.user.account_users.find_by(account_id: @link.account_id)
    return false unless membership

    context = { user: Current.user, account: Current.account, account_user: membership }
    # The principal owns staffing. Transport access does not grant access to the
    # partner's conversations; their existing ConversationPolicy remains unchanged.
    Pundit.policy_scope!(context, Inbox).exists?(id: @link.primary_inbox_id)
  end

  def meta_can_reply?
    message = Message.new(account: @link.account, inbox: @link.inbox_for('whatsapp_cloud'), conversation: @conversation)
    !!Whatsapp::UnifiedTransportService.new(message: message).can_reply?
  end
end
