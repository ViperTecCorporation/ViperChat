class Conversations::LinksService
  PAGE_SIZE = 25
  URL_PATTERN = %r{(?:https?://|www\.)[^\s<>"']+}i

  def self.revision_key(conversation_id)
    ['conversation-links-revision', conversation_id]
  end

  def self.expire(message)
    return unless message.destroyed? || message.saved_change_to_content? || message.saved_change_to_content_attributes?
    return unless [message.content, message.content_before_last_save].any? { |content| content.to_s.match?(URL_PATTERN) }

    Rails.cache.write(revision_key(message.conversation_id), SecureRandom.uuid)
  end

  def initialize(conversation)
    @conversation = conversation
  end

  def perform(page: 1)
    page = [page.to_i, 1].max
    revision = Rails.cache.read(self.class.revision_key(@conversation.id)) || 'initial'
    rows = Rails.cache.fetch(['conversation-links-v2', @conversation.account_id, @conversation.id, revision], expires_in: 5.minutes) do
      extract_links
    end
    offset = (page - 1) * PAGE_SIZE
    { payload: rows.slice(offset, PAGE_SIZE) || [], total_count: rows.length, has_more: offset + PAGE_SIZE < rows.length }
  end

  private

  def extract_links
    @conversation.messages.where(account_id: @conversation.account_id).where.not(message_type: :activity)
                 .where("content ~* '(https?://|www[.])'").reorder(created_at: :desc, id: :desc)
                 .pluck(:id, :content, :created_at, :message_type, :content_attributes).flat_map do |id, content, created_at, type, attributes|
      next [] if attributes['deleted']

      content.scan(URL_PATTERN).map { |url| normalize_url(url) }.uniq.filter_map do |url|
        next if url.blank?

        { url: url, message_id: id, created_at: created_at.to_i,
          message: { id: id, content: content, message_type: Message.message_types[type], attachments: [] } }
      end
    end
  end

  def normalize_url(url)
    url = url.sub(/[.,;:!?]+\z/, '')
    url = url.chop while url.end_with?(')') && url.count(')') > url.count('(')
    url = "https://#{url}" if url.match?(/\Awww\./i)
    uri = URI.parse(url)
    url if uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    nil
  end
end
