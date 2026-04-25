class Messages::LinkPreviewService
  HTML_CONTENT_TYPES = %w[text/html application/xhtml+xml].freeze
  MAX_HTML_BYTES = 2.megabytes
  URL_REGEX = URI::DEFAULT_PARSER.make_regexp(%w[http https])
  TRAILING_URL_PUNCTUATION = /[)\].,!?;:'"]+\z/

  def initialize(message)
    @message = message
  end

  def perform
    return if message.blank? || message.link_preview.present?
    return unless message.text? && message.content.present?

    url = extract_first_url(message.content)
    return if url.blank?

    preview = fetch_preview(url)
    return if preview.blank?

    message.update!(content_attributes: message.content_attributes.to_h.merge('link_preview' => preview))
  rescue SafeFetch::Error, ArgumentError, Nokogiri::XML::SyntaxError => e
    Rails.logger.info "Skipping link preview for message #{message&.id}: #{e.message}"
  end

  private

  attr_reader :message

  def extract_first_url(content)
    content.to_s[URL_REGEX]&.gsub(TRAILING_URL_PUNCTUATION, '')
  end

  def fetch_preview(url)
    SafeFetch.fetch(
      url,
      max_bytes: MAX_HTML_BYTES,
      allowed_content_type_prefixes: [],
      allowed_content_types: HTML_CONTENT_TYPES
    ) do |result|
      build_preview(url, result.tempfile.read)
    end
  end

  def build_preview(url, html)
    document = Nokogiri::HTML(html)
    preview = {
      'url' => normalize_url(meta_content(document, 'og:url').presence || url, url),
      'title' => preview_title(document),
      'description' => meta_content(document, 'og:description', 'twitter:description', 'description')&.truncate(280),
      'image_url' => normalize_url(meta_content(document, 'og:image', 'twitter:image'), url),
      'site_name' => site_name(document, url),
      'favicon_url' => favicon_url(document, url)
    }.compact

    return if preview.values_at('title', 'description', 'image_url').all?(&:blank?)

    preview
  end

  def preview_title(document)
    (meta_content(document, 'og:title', 'twitter:title') || text_content(document.at_css('title')))&.truncate(160)
  end

  def site_name(document, url)
    meta_content(document, 'og:site_name')&.truncate(80) || URI.parse(url).host
  rescue URI::InvalidURIError
    nil
  end

  def meta_content(document, *keys)
    meta_nodes = document.xpath('//meta')

    keys.each do |key|
      node = meta_nodes.find do |meta|
        [meta['property'], meta['name']].compact.any? { |value| value.casecmp?(key) }
      end
      content = text_content(node&.[]('content'))
      return content if content.present?
    end

    nil
  end

  def text_content(value)
    value.to_s.squish.presence
  end

  def normalize_url(value, base_url)
    return if value.blank?

    uri = URI.join(base_url, value.to_s.strip)
    return unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

    uri.to_s.truncate(2048)
  rescue URI::InvalidURIError
    nil
  end

  def favicon_url(document, url)
    icon_link = document.at_css("link[rel~='icon'], link[rel='shortcut icon'], link[rel='apple-touch-icon']")
    icon_href = icon_link&.[]('href')

    normalize_url(icon_href, url) || normalize_url('/favicon.ico', url)
  end
end
