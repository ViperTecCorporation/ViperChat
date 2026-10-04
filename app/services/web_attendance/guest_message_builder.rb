class WebAttendance::GuestMessageBuilder
  include FileTypeHelper

  def initialize(conversation, params)
    @conversation = conversation
    @params = params
  end

  def perform
    request_id = @params.require(:request_id).to_s
    raise ArgumentError, 'Invalid request id' unless request_id.match?(/\A[\w-]{8,80}\z/)

    existing = current_cycle_messages.where(delivery_destination: 'web', sender: @conversation.contact)
                                     .with_content_attribute('web_request_id', request_id).first
    return existing if existing

    message = @conversation.messages.build(
      account: @conversation.account, inbox: @conversation.inbox, sender: @conversation.contact,
      message_type: :incoming, delivery_destination: 'web', content: @params[:content].to_s.first(10_000),
      content_attributes: { web_request_id: request_id }
    )
    attach_files(message)
    raise ArgumentError, 'Message is empty' if message.content.blank? && message.attachments.empty?

    message.save!
    message
  end

  private

  def current_cycle_messages
    boundary = @conversation.web_attendance_start_message_id
    return @conversation.messages.where('id >= ?', boundary) if boundary

    @conversation.messages.where('created_at >= ?', @conversation.web_attendance_started_at)
  end

  def attach_files(message)
    files = Array(@params[:attachments])
    raise ArgumentError, 'Too many attachments' if files.size > 5

    files.each do |upload|
      raise ArgumentError, 'Invalid attachment' unless upload.is_a?(ActionDispatch::Http::UploadedFile)

      message.attachments.build(account: @conversation.account, file: upload, file_type: file_type(upload.content_type))
    end
  end
end
