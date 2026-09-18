# Turns an AsaaS webhook event about a payment into the two things the sales
# flow needs to hear about: a row in the per-instalment audit trail, and — on
# the first paid parcel — the same conversion the manual "Registrar pagamento
# AsaaS" button runs (Stripe customer, out-of-band paid invoice, AurisChat
# account, ClickUp sync).
#
# Payments AsaaS delivers that we cannot tie to a sale (unknown installment
# id, deleted quote, non-payment event, etc.) are dropped silently — AsaaS
# retries an unacknowledged webhook until it gets a 200, so raising here
# would flood the retry queue rather than protect anything.
class Webhooks::Asaas::PaymentEventHandler
  # AsaaS emits many events; only a subset affects an installment payment's
  # lifecycle from our side. Every other event (payment created, transfer,
  # etc.) is acknowledged and ignored.
  STATUS_BY_EVENT = {
    'PAYMENT_RECEIVED' => :received,
    'PAYMENT_CONFIRMED' => :confirmed,
    'PAYMENT_OVERDUE' => :overdue,
    'PAYMENT_REFUNDED' => :refunded,
    'PAYMENT_DELETED' => :deleted
  }.freeze

  # A "money in" event is the trigger for the one-shot conversion of the sale.
  MONEY_IN_EVENTS = %w[PAYMENT_RECEIVED PAYMENT_CONFIRMED].freeze

  def initialize(event:, payment:)
    @event = event.to_s
    @payment = payment || {}
  end

  def perform
    return unless STATUS_BY_EVENT.key?(event)
    return if installment_id.blank?

    quote = SalesQuote.find_by(asaas_installment_id: installment_id)
    return if quote.blank?

    record = upsert_installment_payment(quote)
    maybe_convert_sale(quote, record)
    record
  end

  private

  attr_reader :event, :payment

  def installment_id
    payment['installment']
  end

  def upsert_installment_payment(quote)
    record = SalesAsaasInstallmentPayment.find_or_initialize_by(asaas_payment_id: payment['id'])
    record.assign_attributes(
      sales_quote: quote,
      asaas_installment_id: installment_id,
      installment_number: payment['installmentNumber'],
      amount_cents: cents(payment['value']),
      status: STATUS_BY_EVENT.fetch(event),
      due_date: parse_date(payment['dueDate']),
      paid_at: parse_datetime(payment['paymentDate']) || parse_datetime(payment['clientPaymentDate']),
      payload: payment
    )
    record.save!
    record
  end

  # First money-in on a sale that has not been settled yet runs the same
  # conversion the manual button runs. RegisterAsaasPaymentService is
  # idempotent (guards on `account_id.present?`), so a duplicate webhook is
  # safe — but the guard on `signed?` here skips the raise entirely.
  def maybe_convert_sale(quote, record)
    return unless MONEY_IN_EVENTS.include?(event)
    return unless record.paid?
    return unless quote.signed?

    Sales::RegisterAsaasPaymentService.new(quote: quote).perform
  rescue Sales::RegisterAsaasPaymentService::InvalidTransition => e
    # A race between two events (or a retry) would land here; the sale is
    # already settled, and the acknowledgement of the webhook is what matters.
    Rails.logger.info("[asaas webhook] convert skipped for #{quote.id}: #{e.message}")
  end

  def cents(reais)
    return 0 if reais.blank?

    (reais.to_f * 100).round
  end

  def parse_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def parse_datetime(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
