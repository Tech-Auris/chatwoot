# Thin wrapper around the Stripe SDK for the Financeiro section. Every caller
# goes through this class (never Stripe::* directly) so credential resolution,
# timeouts and error translation stay uniform.
#
# The key is always passed per request instead of assigning `Stripe.api_key`.
# That global is process-wide, so mutating it from a request would leak the
# credential across threads under Puma and would also stomp on the Chatwoot
# Cloud billing services that read it from the environment.
#
# Error hierarchy is intentionally shallow — screens only need to tell
# "the key is wrong, tell the admin" from "Stripe hiccuped, retry".
class Integrations::Stripe::Client
  DEFAULT_TIMEOUT = 15
  PRODUCT_LIST_LIMIT = 100
  # Invoice due window when none is given. A week matches how the team already
  # bills by PIX: the invoice goes out, the customer pays within the period.
  DEFAULT_DAYS_UNTIL_DUE = 7
  # Reverse pointer stamped on the Stripe customer so the pairing is auditable
  # from the Stripe dashboard, not only from our database.
  ACCOUNT_METADATA_KEY = 'aurischat_account_id'.freeze
  # Where a payment received outside Stripe came in. Stamped on the invoice so
  # "how much came through AsaaS this month" is answerable from Stripe itself,
  # without a table of our own to keep in sync.
  PAID_VIA_METADATA_KEY = 'aurischat_paid_via'.freeze
  PAID_VIA_SOURCES = %w[inter asaas].freeze
  # Marks how an invoice was issued, so a batch can be recognized later.
  BILLING_SOURCE_METADATA_KEY = 'aurischat_billing_source'.freeze
  BILLING_PERIOD_METADATA_KEY = 'aurischat_billing_period'.freeze
  INVOICE_PAGE_SIZE = 25

  class Error < StandardError; end
  class Unauthorized < Error; end
  class ProviderUnavailable < Error; end
  class InvalidRequest < Error; end

  def initialize(api_key: nil)
    @api_key = api_key.presence || GlobalConfig.get('STRIPE_SECRET_KEY')['STRIPE_SECRET_KEY'].presence || ENV.fetch('STRIPE_SECRET_KEY', nil)
  end

  def configured?
    @api_key.present?
  end

  # Stripe's Account object carries no `livemode` flag (other resources do), so
  # the environment is read off the key itself: every publishable, secret and
  # restricted key embeds `_test_` or `_live_`. Anything else is reported as
  # unknown rather than optimistically assumed to be live.
  def key_mode
    return :test if @api_key.to_s.include?('_test_')
    return :live if @api_key.to_s.include?('_live_')

    :unknown
  end

  # Account behind the configured key. Used by the "test connection" panel to
  # prove the credential works and to surface whether it is a live or test key
  # before anyone charges a real customer.
  # `Account.retrieve(id = nil, opts = {})` validates the first argument as a
  # string when it is truthy, so the id has to be an explicit nil — passing an
  # empty hash there raises "argument must be a string" before any HTTP call.
  def account
    with_error_handling { Stripe::Account.retrieve(nil, request_options) }
  end

  def list_products(limit: PRODUCT_LIST_LIMIT)
    with_error_handling do
      Stripe::Product.list({ limit: limit, expand: ['data.default_price'] }, request_options)
    end
  end

  def create_product(name:, description: nil, active: true)
    with_error_handling do
      Stripe::Product.create({ name: name, description: description.presence, active: active }.compact, request_options)
    end
  end

  # Only the mutable fields are exposed. A Stripe product cannot change its id
  # and its prices are edited through their own endpoints.
  def update_product(product_id, attributes)
    with_error_handling { Stripe::Product.update(product_id, attributes, request_options) }
  end

  # Stripe only deletes products that never had a price; everything else is
  # archived. Archiving is what the ops team wants anyway — a deleted product
  # would break the invoices that reference it.
  def archive_product(product_id)
    update_product(product_id, { active: false })
  end

  def list_prices(product_id: nil, limit: PRODUCT_LIST_LIMIT)
    with_error_handling do
      Stripe::Price.list({ product: product_id, limit: limit }.compact, request_options)
    end
  end

  # A Stripe price is immutable: changing an amount means creating a new price
  # and archiving the old one. Callers surface that as "novo preço", never as
  # an edit.
  def create_price(product_id:, unit_amount:, currency:, recurring_interval: nil)
    payload = { product: product_id, unit_amount: unit_amount, currency: currency }
    payload[:recurring] = { interval: recurring_interval } if recurring_interval.present?

    with_error_handling { Stripe::Price.create(payload, request_options) }
  end

  def archive_price(price_id)
    with_error_handling { Stripe::Price.update(price_id, { active: false }, request_options) }
  end

  # Every customer on the account. `auto_paging_each` walks past the 100-item
  # page cap, which matters as soon as the catalog outgrows a single page.
  def list_customers
    with_error_handling do
      Stripe::Customer.list({ limit: PRODUCT_LIST_LIMIT }, request_options).auto_paging_each.to_a
    end
  end

  # The account id rides on `metadata` so the link is readable from the Stripe
  # dashboard and can be rebuilt from Stripe if our column is ever lost.
  def create_customer(name:, email: nil, account_id: nil)
    payload = { name: name, email: email.presence }.compact
    payload[:metadata] = { ACCOUNT_METADATA_KEY => account_id.to_s } if account_id.present?

    with_error_handling { Stripe::Customer.create(payload, request_options) }
  end

  def link_customer_to_account(customer_id, account_id)
    with_error_handling do
      Stripe::Customer.update(customer_id, { metadata: { ACCOUNT_METADATA_KEY => account_id.to_s } }, request_options)
    end
  end

  # Clearing a metadata key on Stripe means sending it as an empty string.
  def unlink_customer(customer_id)
    with_error_handling do
      Stripe::Customer.update(customer_id, { metadata: { ACCOUNT_METADATA_KEY => '' } }, request_options)
    end
  end

  # Every subscription, in any state. `status: 'all'` is what surfaces the
  # canceled and past_due ones — the default only returns the healthy ones,
  # which are exactly the rows nobody needs to look at.
  def list_subscriptions
    with_error_handling do
      Stripe::Subscription.list({ status: 'all', limit: PRODUCT_LIST_LIMIT }, request_options).auto_paging_each.to_a
    end
  end

  # Subscriptions are created to bill by invoice, never by card charge: part of
  # the customers pay by PIX outside Stripe (Banco Inter, AsaaS), and an
  # automatic charge would fail for exactly those. The invoice keeps Stripe as
  # the record of what was billed, and a payment received elsewhere is written
  # off against it (see `pay_invoice_out_of_band`).
  def create_subscription(customer_id:, price_id:, quantity: 1, days_until_due: DEFAULT_DAYS_UNTIL_DUE, coupon_id: nil)
    with_error_handling do
      Stripe::Subscription.create(
        {
          customer: customer_id,
          items: [{ price: price_id, quantity: quantity }],
          collection_method: 'send_invoice',
          days_until_due: days_until_due,
          # `discounts` is the parameter in this API version; the older `coupon`
          # is accepted silently by the SDK and dropped, leaving a subscription
          # billed at full price with nobody the wiser.
          discounts: discounts_for(coupon_id)
        }.compact,
        request_options
      )
    end
  end

  # Invoices, newest first. Stripe pages with a cursor rather than an offset, so
  # the caller passes the id of the last row it already has.
  def list_invoices(status: nil, customer_id: nil, limit: INVOICE_PAGE_SIZE, starting_after: nil)
    payload = { status: status.presence, customer: customer_id.presence, limit: limit, starting_after: starting_after.presence }.compact

    with_error_handling { Stripe::Invoice.list(payload, request_options) }
  end

  # Issues an invoice for a customer.
  #
  # The invoice is created empty first and every item is bound to it by id:
  # an invoice item created loose would sit as "pending" on the customer and be
  # swept into whatever invoice closes next — including the subscription's.
  #
  # Finalizing is what turns a draft into a collectible invoice, which is the
  # state the write-off and the payment link need. Sending the e-mail is left
  # to Stripe's own invoice settings; nothing here mails the customer.
  #
  # Items are either a catalog price (`price_id` + quantity) or a free amount
  # (`description` + `unit_amount` in cents).
  # `options` carries the optional side of an invoice: `days_until_due`,
  # `description`, `metadata` and `coupon_id`.
  def create_invoice(customer_id:, items:, **options)
    raise InvalidRequest, 'A fatura precisa de pelo menos um item' if items.blank?

    with_error_handling do
      invoice = Stripe::Invoice.create(
        { customer: customer_id, collection_method: 'send_invoice',
          days_until_due: options[:days_until_due].presence || DEFAULT_DAYS_UNTIL_DUE,
          description: options[:description].presence, metadata: options[:metadata].presence, auto_advance: false,
          discounts: discounts_for(options[:coupon_id]),
          # Anything left pending on the customer by another flow stays out of
          # this invoice. A token charge must carry the token lines and nothing
          # else, whatever else is queued on that customer.
          pending_invoice_item_behavior: 'exclude' }.compact,
        request_options
      )
      items.each { |item| create_invoice_item(invoice.id, customer_id, item) }
      Stripe::Invoice.finalize_invoice(invoice.id, {}, request_options)
    end
  end

  # Coupons available to be applied on a subscription or an invoice. Stripe has
  # no "archived" state for a coupon: it either exists or is deleted, and a
  # deleted one keeps applying to whoever already redeemed it.
  def list_coupons(limit: PRODUCT_LIST_LIMIT)
    with_error_handling { Stripe::Coupon.list({ limit: limit }, request_options) }
  end

  # Either a percentage or a fixed amount, never both — Stripe refuses the pair.
  # `product_ids` restricts the discount to those products, which is how a
  # coupon applies to one line of a subscription instead of the whole bill.
  def create_coupon(attributes)
    attributes = attributes.symbolize_keys
    percent_off = attributes[:percent_off]
    amount_off = attributes[:amount_off]
    raise InvalidRequest, 'Informe um percentual ou um valor de desconto' if percent_off.blank? && amount_off.blank?
    raise InvalidRequest, 'Escolha percentual ou valor, não os dois' if percent_off.present? && amount_off.present?

    with_error_handling { Stripe::Coupon.create(coupon_payload(attributes), request_options) }
  end

  # Deleting only stops the coupon from being applied again; discounts already
  # granted stay on the subscriptions that redeemed it.
  def delete_coupon(coupon_id)
    with_error_handling { Stripe::Coupon.delete(coupon_id, {}, request_options) }
  end

  # Hosted checkout for the sales flow. Installments are a Brazilian card
  # feature enabled on the account; the cap comes from the plan the customer
  # picked, and Stripe filters the offered plans down to it.
  # `options` carries `max_installments` and `metadata`.
  def create_checkout_session(customer_id:, line_items:, urls:, **options)
    payload = {
      mode: 'payment',
      customer: customer_id,
      line_items: line_items,
      success_url: urls.fetch(:success),
      cancel_url: urls.fetch(:cancel),
      metadata: options[:metadata] || {},
      payment_method_types: ['card']
    }
    payload[:payment_method_options] = installment_options(options[:max_installments]) if options[:max_installments].to_i > 1

    with_error_handling { Stripe::Checkout::Session.create(payload, request_options) }
  end

  def retrieve_checkout_session(session_id)
    with_error_handling { Stripe::Checkout::Session.retrieve(session_id, request_options) }
  end

  # Writes off an invoice paid outside Stripe (PIX at Banco Inter or AsaaS).
  #
  # The payment is registered first and the origin stamped after: if the stamp
  # failed we would have an invoice marked as paid missing only its source,
  # which someone can fix. The reverse order could leave an unpaid invoice
  # carrying a source, which reads as money that came in and did not.
  def pay_invoice_out_of_band(invoice_id, paid_via:)
    raise InvalidRequest, "Origem inválida: #{paid_via}" unless PAID_VIA_SOURCES.include?(paid_via.to_s)

    with_error_handling do
      invoice = Stripe::Invoice.pay(invoice_id, { paid_out_of_band: true }, request_options)
      Stripe::Invoice.update(invoice_id, { metadata: { PAID_VIA_METADATA_KEY => paid_via.to_s } }, request_options)
      invoice
    end
  end

  private

  def installment_options(max_installments)
    { card: { installments: { enabled: true,
                              plan: { count: max_installments.to_i, interval: 'month', type: 'fixed_count' } } } }
  end

  def discounts_for(coupon_id)
    return nil if coupon_id.blank?

    [{ coupon: coupon_id }]
  end

  def coupon_payload(attributes)
    duration = attributes[:duration].presence || 'once'
    payload = { name: attributes[:name], duration: duration }
    payload[:duration_in_months] = attributes[:duration_in_months].to_i if duration == 'repeating'
    payload[:max_redemptions] = attributes[:max_redemptions].to_i if attributes[:max_redemptions].present?
    payload[:applies_to] = { products: Array(attributes[:product_ids]) } if attributes[:product_ids].present?
    payload.merge(coupon_discount(attributes))
  end

  def coupon_discount(attributes)
    return { percent_off: attributes[:percent_off].to_f } if attributes[:percent_off].present?

    { amount_off: attributes[:amount_off].to_i, currency: attributes[:currency].presence || 'brl' }
  end

  def create_invoice_item(invoice_id, customer_id, item)
    payload = { customer: customer_id, invoice: invoice_id }

    if item[:price_id].present?
      payload[:price] = item[:price_id]
      payload[:quantity] = item[:quantity].presence || 1
    else
      # A free amount carries the whole line total, so the quantity is folded
      # into it — Stripe rejects `amount` together with `quantity`.
      payload[:amount] = item[:unit_amount].to_i * (item[:quantity].presence || 1).to_i
      payload[:currency] = item[:currency].presence || 'brl'
      payload[:description] = item[:description].presence || 'Cobrança avulsa'
    end

    Stripe::InvoiceItem.create(payload, request_options)
  end

  def request_options
    { api_key: @api_key }
  end

  def with_error_handling
    raise Unauthorized, 'STRIPE_SECRET_KEY is not configured' unless configured?

    yield
  rescue ::Stripe::AuthenticationError, ::Stripe::PermissionError => e
    raise Unauthorized, e.message
  rescue ::Stripe::InvalidRequestError => e
    raise InvalidRequest, e.message
  rescue ::Stripe::APIConnectionError, ::Stripe::APIError => e
    raise ProviderUnavailable, e.message
  end
end
