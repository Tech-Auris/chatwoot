# Fetches the terms of use as they read right now and freezes that copy.
#
# The signature points at the frozen copy, never at the live page: the page can
# be edited at any moment, and a contract that changes after it was signed is
# not something anybody can audit.
class Sales::TermsFetcherService
  # The public terms page. Overridable via `SALES_TERMS_URL` on Super
  # Admin → Settings when marketing rehosts it.
  DEFAULT_URL = 'https://www.auris.ia.br/termos-de-uso'.freeze
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

    TermsVersion.for_content(@url, content, document_date: extract_document_date(content))
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

  # The marketing page stamps its own edition as "Última atualização: 3 de
  # Set de 2026." The date drives the report on Super Admin — knowing the
  # exact wording is next to it lets the super_admin confirm the version
  # they are asking managers to sign. Absent or unparseable, the wizard
  # falls back to a manual input.
  DATE_PATTERN = /Última atualização:\s*(\d{1,2})\s*de\s*([A-Za-zçãé]+)\s*de\s*(\d{4})/i
  MONTHS = {
    'jan' => 1, 'janeiro' => 1,
    'fev' => 2, 'fevereiro' => 2,
    'mar' => 3, 'março' => 3, 'marco' => 3,
    'abr' => 4, 'abril' => 4,
    'mai' => 5, 'maio' => 5,
    'jun' => 6, 'junho' => 6,
    'jul' => 7, 'julho' => 7,
    'ago' => 8, 'agosto' => 8,
    'set' => 9, 'setembro' => 9,
    'out' => 10, 'outubro' => 10,
    'nov' => 11, 'novembro' => 11,
    'dez' => 12, 'dezembro' => 12
  }.freeze

  def extract_document_date(content)
    match = content.match(DATE_PATTERN)
    return if match.nil?

    day = match[1].to_i
    month = MONTHS[match[2].downcase]
    year = match[3].to_i
    return if month.nil?

    Date.new(year, month, day)
  rescue Date::Error
    nil
  end
end
