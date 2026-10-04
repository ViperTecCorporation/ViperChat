class WebAttendance::MessagePresenter
  def initialize(message)
    @message = message
  end

  def as_json
    {
      id: @message.id, content: @message.content, message_type: @message.message_type_before_type_cast,
      created_at: @message.created_at.to_i, delivery_destination: @message.delivery_destination, status: @message.status,
      view_once: @message.content_attributes['view_once'] == true,
      sender: { name: @message.sender&.name }, attachments: @message.attachments.map { |attachment| attachment_data(attachment) }
    }
  end

  private

  def attachment_data(attachment)
    {
      id: attachment.id, file_type: attachment.file_type, name: attachment.file.attached? ? attachment.file.filename.to_s : nil,
      url: "/web-attendance/api/attachments/#{attachment.id}", meta: attachment.contact? ? attachment.meta : {},
      fallback_title: attachment.fallback_title, latitude: attachment.coordinates_lat, longitude: attachment.coordinates_long
    }
  end
end
