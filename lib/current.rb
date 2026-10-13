module Current
  thread_mattr_accessor :user
  thread_mattr_accessor :account
  thread_mattr_accessor :account_user
  thread_mattr_accessor :executed_by
  thread_mattr_accessor :contact
  thread_mattr_accessor :inbox
  thread_mattr_accessor :web_attendance_conversation_id
  thread_mattr_accessor :web_attendance_contact_id

  def self.with_web_attendance(conversation)
    previous_id = web_attendance_conversation_id
    previous_contact_id = web_attendance_contact_id
    self.web_attendance_conversation_id = conversation.id
    self.web_attendance_contact_id = conversation.contact_id
    yield
  ensure
    self.web_attendance_conversation_id = previous_id
    self.web_attendance_contact_id = previous_contact_id
  end

  def self.reset
    Current.user = nil
    Current.account = nil
    Current.account_user = nil
    Current.executed_by = nil
    Current.contact = nil
    Current.inbox = nil
    Current.web_attendance_conversation_id = nil
    Current.web_attendance_contact_id = nil
  end
end
