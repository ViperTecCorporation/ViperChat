class Dispatcher
  include Singleton

  attr_reader :async_dispatcher, :sync_dispatcher

  def self.dispatch(event_name, timestamp, data, async = false)
    Rails.configuration.dispatcher.dispatch(event_name, timestamp, data, async)
  end

  def initialize
    @sync_dispatcher = SyncDispatcher.new
    @async_dispatcher = AsyncDispatcher.new
  end

  def dispatch(event_name, timestamp, data, _async = false)
    data = data.merge(web_attendance: true) if web_attendance_event?(data)
    @sync_dispatcher.dispatch(event_name, timestamp, data)
    @async_dispatcher.dispatch(event_name, timestamp, data)
  end

  def load_listeners
    @sync_dispatcher.load_listeners
    @async_dispatcher.load_listeners
  end

  private

  def web_attendance_event?(data)
    message = data[:message]
    conversation = data[:conversation] || message&.conversation
    contact = data[:contact]
    message&.web_attendance? || (conversation && Current.web_attendance_conversation_id == conversation.id) ||
      (contact && Current.web_attendance_contact_id == contact.id)
  end
end
