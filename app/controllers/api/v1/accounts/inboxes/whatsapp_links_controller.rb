class Api::V1::Accounts::Inboxes::WhatsappLinksController < Api::V1::Accounts::BaseController
  require_account_feature 'inbox_management'
  before_action :fetch_inbox

  def show
    link = existing_link
    authorize_pair(link) if link
    render json: payload(link)
  end

  def preview
    link = proposed_link
    link.validate!
    render json: payload(link, Whatsapp::InboxLinkPreviewService.new(link: link).perform)
  end

  def update
    Current.account.with_lock do
      link = proposed_link
      link.validate!
      service = Whatsapp::InboxLinkPreviewService.new(link: link)
      preview = service.perform
      if link.enabled? && !link.enabled_in_database && preview[:confirmation_required] && !service.confirmed?(params[:confirmation], preview)
        render json: payload(link, preview).merge(error: 'preview_confirmation_required'), status: :conflict
        next
      end

      link.save!
      audit_change(link)
      render json: payload(link, preview.merge(cutoff: link.activated_at))
    end
  end

  def destroy
    Current.account.with_lock do
      link = existing_link
      if link
        authorize_pair(link)
        link.update!(enabled: false)
        audit_change(link)
      end
      render json: payload(link)
    end
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize @inbox, :update?
  end

  def existing_link
    WhatsappInboxLink.where(account_id: Current.account.id).covering(@inbox.id).order(enabled: :desc, updated_at: :desc, id: :desc).first
  end

  def proposed_link
    link = existing_link || WhatsappInboxLink.new(account: Current.account, default_provider: 'unoapi')
    authorize_pair(link) if link.persisted?
    partner = proposed_partner(link)
    primary, secondary = ordered_pair(link, partner)
    link.assign_attributes(permitted_params.merge(primary_inbox: primary, secondary_inbox: secondary))
    link
  end

  def proposed_partner(link)
    partner = if params[:partner_inbox_id].present?
                Current.account.inboxes.find(params[:partner_inbox_id])
              else
                link.partner_for(@inbox)
              end
    raise ActiveRecord::RecordNotFound unless partner

    authorize partner, :update?
    partner
  end

  def ordered_pair(link, partner)
    primary_id = params[:primary_inbox_id].presence || link.primary_inbox_id
    unless [@inbox.id, partner.id].include?(primary_id.to_i)
      link.errors.add(:primary_inbox_id, 'must explicitly select one inbox of the pair')
      raise ActiveRecord::RecordInvalid, link
    end
    primary_id.to_i == @inbox.id ? [@inbox, partner] : [partner, @inbox]
  end

  def permitted_params
    params.permit(:default_provider, :enabled, :meta_initial_messages_enabled, :meta_initial_messages_limit).to_h
  end

  def authorize_pair(link)
    authorize link.primary_inbox, :update?
    authorize link.secondary_inbox, :update?
  end

  def payload(link, preview = nil)
    preview ||= link ? Whatsapp::InboxLinkPreviewService.new(link: link).perform : { conflicts: [], confirmation_required: false }
    {
      link: link&.slice(:id, :primary_inbox_id, :secondary_inbox_id, :default_provider, :enabled, :activated_at,
                        :meta_initial_messages_enabled, :meta_initial_messages_limit),
      candidates: candidates, preview: preview
    }
  end

  def audit_change(link)
    Rails.logger.info({
      event: 'whatsapp_inbox_link_updated', account_id: Current.account.id, actor_id: Current.user.id, link_id: link.id,
      changes: link.previous_changes.slice('primary_inbox_id', 'secondary_inbox_id', 'default_provider', 'enabled', 'activated_at',
                                           'meta_initial_messages_enabled', 'meta_initial_messages_limit')
    }.to_json)
  end

  def candidates
    return [] unless @inbox.whatsapp? && WhatsappInboxLink::PROVIDERS.include?(@inbox.channel.provider)

    phone = Whatsapp::InboxLinkPhoneService.normalize(@inbox.channel.phone_number)
    return [] unless phone

    available = policy_scope(Current.account.inboxes).where(channel_type: 'Channel::Whatsapp').where.not(id: @inbox.id).includes(:channel)
    available.filter_map do |candidate|
      next unless candidate_matches?(candidate, phone)

      { id: candidate.id, name: candidate.name, provider: candidate.channel.provider }
    end
  end

  def candidate_matches?(candidate, phone)
    return false unless WhatsappInboxLink::PROVIDERS.include?(candidate.channel.provider) && candidate.channel.provider != @inbox.channel.provider
    return false unless Whatsapp::InboxLinkPhoneService.normalize(candidate.channel.phone_number) == phone

    active_link = WhatsappInboxLink.for_inbox(candidate)
    !active_link || active_link.covers?(@inbox)
  end
end

Api::V1::Accounts::Inboxes::WhatsappLinksController.prepend_mod_with('Api::V1::Accounts::Inboxes::WhatsappLinksController')
