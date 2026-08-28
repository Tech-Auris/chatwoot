# The Stripe customer behind a proposal.
#
# Everything the prospect typed on our form is pushed onto it, so the payment
# page opens filled in instead of asking for the same data twice — and so the
# invoices of a PIX customer, who never sees a Stripe page, still carry the
# right name and document.
class Sales::StripeCustomerService
  def initialize(quote:, client: nil)
    @quote = quote
    @client = client
  end

  # Reuses the customer the proposal already points at; creates one otherwise.
  # Safe to call again — a retried checkout lands here a second time.
  def ensure!
    id = quote.stripe_customer_id.presence || client.create_customer(name: billing_name, email: quote.prospect_email).id
    client.update_customer(id, name: billing_name, email: quote.prospect_email, phone: quote.prospect_phone)
    attach_tax_id(id)
    id
  end

  private

  attr_reader :quote

  def client
    @client ||= Integrations::Stripe::Client.new
  end

  # The invoice is issued against the company when the customer asked for it,
  # and against the person otherwise.
  def billing_name
    quote.billing_name.presence || quote.company_name.presence || quote.prospect_name
  end

  # A CNPJ when there is one, the CPF otherwise. Stripe rejects a repeated tax
  # id, and a retried checkout would hit exactly that.
  def attach_tax_id(customer_id)
    document = quote.company_document.presence || quote.prospect_document
    digits = document.to_s.gsub(/\D/, '')
    return if digits.blank?

    type = digits.length > 11 ? 'br_cnpj' : 'br_cpf'
    return if client.list_tax_ids(customer_id).data.any? { |tax_id| tax_id.value.to_s.gsub(/\D/, '') == digits }

    client.create_tax_id(customer_id, type: type, value: document)
  rescue Integrations::Stripe::Client::InvalidRequest => e
    # A document Stripe refuses must not stop the sale; the customer can type it
    # on the payment page.
    Rails.logger.info("[sales] tax id not attached to #{customer_id}: #{e.message}")
  end
end
