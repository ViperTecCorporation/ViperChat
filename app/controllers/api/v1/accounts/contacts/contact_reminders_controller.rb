class Api::V1::Accounts::Contacts::ContactRemindersController < Api::V1::Accounts::Contacts::BaseController
  before_action :contact_reminder, except: [:index, :create]

  def index
    @contact_reminders = @contact.contact_reminders.order(scheduled_at: :asc).includes(:user)
  end

  def show; end

  def create
    @contact_reminder = @contact.contact_reminders.create!(contact_reminder_params)
  end

  def update
    @contact_reminder.update!(contact_reminder_params)
  end

  def destroy
    @contact_reminder.destroy!
    head :ok
  end

  private

  def contact_reminder
    @contact_reminder ||= @contact.contact_reminders.find(params[:id])
  end

  def contact_reminder_params
    params.require(:contact_reminder).permit(
      :conversation_id,
      :scheduled_at,
      :send_message,
      :message_content,
      :is_completed
    ).merge({ user_id: Current.user.id })
  end
end
