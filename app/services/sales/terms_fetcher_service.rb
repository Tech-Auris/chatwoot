# Fetches the terms of use as they read right now and freezes that copy.
#
# The signature points at the frozen copy, never at the live page: the page can
# be edited at any moment, and a contract that changes after it was signed is
# not something anybody can audit.
class Sales::TermsFetcherService
  DEFAULT_URL = 'https://agenteauris.com.br/termos-de-uso/'.freeze
  TIMEOUT = 10

  class Unavailable < StandardError; end

  def initialize(url: nil)
    @url = url.presence || GlobalConfig.get('SALES_TERMS_URL')['SALES_TERMS_URL'].presence || DEFAULT_URL
  end

  def perform
    response = HTTParty.get(@url, timeout: TIMEOUT, follow_redirects: true)
    raise Unavailable, "Termos indisponíveis (HTTP #{response.code})" unless response.success?

    content = extract_content(response.body)
    raise Unavailable, 'Os termos vieram vazios' if content.blank?

    TermsVersion.for_content(@url, content)
  rescue HTTParty::Error, SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
    raise Unavailable, "Não foi possível carregar os termos: #{e.message}"
  rescue ActiveRecord::RecordInvalid => e
    # The page is reachable but what came back cannot be stored. Saying so on
    # the proposal beats the generic error page the exception would produce.
    raise Unavailable, "Não foi possível registrar os termos: #{e.record.errors.full_messages.to_sentence}"
  end

  private

  # Only the readable text is kept. Storing the raw page would make the hash
  # change on every unrelated markup tweak, and every such change would look
  # like a new contract in the audit trail.
  # Formatting is kept — headings, lists and emphasis are how a contract is read
  # — but only from a fixed set of tags, and with scripts, styles and the site
  # chrome dropped first.
  #
  # The trade-off is deliberate: a purely visual change on the site produces a
  # different hash and therefore a new version, even though the wording did not
  # move. Better a duplicate in the audit trail than a contract nobody can read.
  ALLOWED_TAGS = %w[p br strong b em i u h1 h2 h3 h4 h5 h6 ul ol li a blockquote table thead tbody tr th td].freeze
  ALLOWED_ATTRIBUTES = %w[href].freeze

  def extract_content(body)
    document = Nokogiri::HTML(body)
    document.search('script, style, nav, header, footer, iframe, form').remove
    main = document.at_css('main') || document.at_css('article') || document.at_css('body') || document

    sanitizer.sanitize(main.inner_html, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES)
             .gsub(/\s*\n\s*/, "\n").squeeze("\n").strip
  end

  def sanitizer
    @sanitizer ||= Rails::HTML5::SafeListSanitizer.new
  end
end
