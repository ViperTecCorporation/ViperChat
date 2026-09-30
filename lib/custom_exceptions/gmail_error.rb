class CustomExceptions::GmailError < StandardError
  attr_reader :status

  def initialize(status)
    @status = status
    super("Gmail API request failed (HTTP #{status})")
  end
end
