# Creates a dynamic PIX cob on Banco Inter for a signed proposal and keeps
# the returned `txid` + `pixCopiaECola` on the quote — that pair is what the
# webhook uses to recognise the payment and what the public page shows the
# customer.
#
# The service is a soft dependency of the PIX flow: if Inter is not
# configured, or the call fails, the sale still finishes and the customer
# falls back to the static PIX code (`Sales::PixCodeService`), which is how
# PIX worked before Inter automation existed. A missing cob only means "no
# webhook reconciliation on this sale" — the finance team can still click
# "Registrar pagamento PIX" by hand.
class Sales::InterPixCobService
  DESCRIPTION_MAX_LENGTH = 140

  def initialize(quote:, client: nil)
    @quote = quote
    @client = client
  end

  # Idempotent: reuses the txid already on the quote (a signed retry lands on
  # the same cob), otherwise creates a new one. Returns the quote either way.
  def ensure_cob!
    return quote if quote.inter_txid.present?
    return quote unless client.configured? && pix_key.present?

    open_cob!
    quote
  rescue Integrations::Inter::Client::Error => e
    # A cob we could not open must not stop the sale — the static PIX flow
    # still works, and the finance team confirms the payment by hand.
    Rails.logger.info("[sales] inter cob not opened for ##{quote.id}: #{e.message}")
    quote.events.create!(event: 'inter_pix_cob_failed', metadata: { error: e.message })
    quote
  end

  private

  def open_cob!
    txid = build_txid
    response = client.create_cob(txid: txid, value_cents: quote.effective_charge_amount,
                                 pix_key: pix_key, description: description, debtor: debtor_payload)

    quote.update!(inter_txid: response['txid'].presence || txid,
                  inter_pix_payload: response['pixCopiaECola'])
    quote.events.create!(event: 'inter_pix_cob_created',
                         metadata: { txid: quote.inter_txid, amount: quote.effective_charge_amount })
  end

  def debtor_payload
    { document: quote.company_document.presence || quote.prospect_document,
      name: quote.company_name.presence || quote.prospect_name }
  end

  attr_reader :quote

  def client
    @client ||= Integrations::Inter::Client.new
  end

  def pix_key
    @pix_key ||= GlobalConfig.get('INTER_PIX_KEY')['INTER_PIX_KEY'].to_s.strip
  end

  # Bacen requires 26..35 alphanumeric characters. The public token is 43
  # base64-url characters — trim to the last 30 to stay safely inside the
  # range while keeping enough entropy to be unique across proposals.
  def build_txid
    "auris#{quote.public_token.gsub(/[^A-Za-z0-9]/, '')}"[0, 30].ljust(26, '0')
  end

  def description
    ['Pagamento Auris', quote.discount_summary.presence].compact.join(' · ')[0, DESCRIPTION_MAX_LENGTH]
  end
end
