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

    TermsVersion.for_content(@url, extract_text(response.body))
  rescue HTTParty::Error, SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
    raise Unavailable, "Não foi possível carregar os termos: #{e.message}"
  end

  private

  # Only the readable text is kept. Storing the raw page would make the hash
  # change on every unrelated markup tweak, and every such change would look
  # like a new contract in the audit trail.
  # Text nodes are joined with a space rather than read off the document as a
  # whole: `.text` glues neighbouring blocks together, turning "Termos" and
  # "Conteúdo" into "TermosConteúdo" — unreadable in a contract somebody may
  # have to consult years later.
  def extract_text(body)
    document = Nokogiri::HTML(body)
    document.search('script, style, nav, header, footer').remove
    document.xpath('//text()').map { |node| node.text.strip }.reject(&:empty?).join(' ').gsub(/[[:space:]]+/, ' ').strip
  end
end
