# Invoices issued by Stripe, and the write-off for the ones paid elsewhere.
#
# Subscriptions here bill by invoice on purpose (see
# `Integrations::Stripe::Client#create_subscription`), because part of the
# customers pay by PIX at Banco Inter or through AsaaS. This screen is where
# that payment is registered against the invoice, keeping Stripe as the single
# record of what was billed and what was settled.
class SuperAdmin::Financial::InvoicesController < SuperAdmin::ApplicationController
  # A search that matched half the base would be a page walk of Stripe, one
  # call per customer; past this many the term was too broad to be useful.
  SEARCH_CUSTOMER_LIMIT = 10

  rescue_from Integrations::Stripe::Client::Unauthorized do |e|
    render json: { error: "Credencial do Stripe inválida: #{e.message}" }, status: :unauthorized
  end

  rescue_from Integrations::Stripe::Client::InvalidRequest do |e|
    render json: { error: e.message }, status: :unprocessable_entity
  end

  rescue_from Integrations::Stripe::Client::ProviderUnavailable do |e|
    render json: { error: "Stripe indisponível: #{e.message}" }, status: :bad_gateway
  end

  before_action :ensure_configured, except: [:index]

  def index; end

  def data
    invoices, has_more = params[:q].present? ? searched_invoices : listed_invoices
    load_account_names(invoices)

    render json: {
      invoices: invoices.map { |invoice| serialize(invoice) },
      accounts: billable_accounts,
      prices: catalog_prices,
      coupons: available_coupons,
      meta: { has_more: has_more, last_id: invoices.last&.id, sources: Integrations::Stripe::Client::PAID_VIA_SOURCES }
    }
  end

  # Issues an invoice on the spot — the monthly token charge, an extra service,
  # anything that is not covered by the subscription.
  def create
    account = Account.find(params[:account_id])
    return render json: { error: 'Conta sem cliente do Stripe vinculado.' }, status: :unprocessable_entity if account.stripe_customer_id.blank?

    invoice = client.create_invoice(
      customer_id: account.stripe_customer_id,
      items: invoice_items,
      days_until_due: params[:days_until_due].presence&.to_i || Integrations::Stripe::Client::DEFAULT_DAYS_UNTIL_DUE,
      description: params[:description],
      coupon_id: params[:coupon_id].presence
    )
    load_account_names([invoice])

    render json: { invoice: serialize(invoice) }, status: :created
  end

  # Marks an invoice as settled outside Stripe, recording where the money came
  # in so the origin is auditable later.
  def pay
    invoice = client.pay_invoice_out_of_band(params[:id], paid_via: params[:paid_via])
    load_account_names([invoice])

    render json: { invoice: serialize(invoice) }
  end

  private

  def listed_invoices
    list = client.list_invoices(status: params[:status], starting_after: params[:starting_after])
    [list.data, list.has_more]
  end

  # Stripe cannot search invoices by who they are for, so the customer is found
  # first and their invoices are read one customer at a time. The result is a
  # single page: somebody chasing a named customer is not paging through
  # thousands of rows.
  def searched_invoices
    ids = matching_customer_ids
    return [[], false] if ids.empty?

    invoices = ids.flat_map { |id| client.list_invoices(status: params[:status], customer_id: id).data }
    [invoices.sort_by { |invoice| -invoice.created.to_i }.first(Integrations::Stripe::Client::INVOICE_PAGE_SIZE), false]
  end

  # The term is matched against Stripe and against our own account names, which
  # drift apart: an account renamed here keeps the name it was sold under in
  # Stripe.
  def matching_customer_ids
    term = params[:q].to_s.strip
    from_stripe = client.search_customers(term).map(&:id)
    from_accounts = Account.where('name ILIKE ?', "%#{term}%").where.not(stripe_customer_id: nil).pluck(:stripe_customer_id)

    (from_stripe + from_accounts).uniq.first(SEARCH_CUSTOMER_LIMIT)
  end

  def client
    @client ||= Integrations::Stripe::Client.new
  end

  def ensure_configured
    return if client.configured?

    render json: { error: 'Stripe não está configurado. Salve a Stripe Secret Key em Settings → Stripe.' },
           status: :unprocessable_entity
  end

  # A line is either a catalog price or a free amount typed by the operator.
  # Amounts arrive in reais and Stripe counts in cents.
  def invoice_items
    Array(params[:items]).filter_map do |item|
      next if item[:price_id].blank? && item[:amount].blank?

      {
        price_id: item[:price_id],
        quantity: item[:quantity].presence&.to_i || 1,
        description: item[:description],
        unit_amount: item[:amount].present? ? (item[:amount].to_f * 100).round : nil
      }
    end
  end

  # Only coupons Stripe still considers usable.
  def available_coupons
    client.list_coupons.data.filter_map do |coupon|
      next unless coupon.valid

      { id: coupon.id, name: coupon.name, percent_off: coupon.percent_off,
        amount_off: coupon.amount_off, currency: coupon.currency, duration: coupon.duration }
    end
  end

  # Only accounts already paired with a Stripe customer can be billed.
  def billable_accounts
    Account.where.not(stripe_customer_id: nil).order(:name).map do |account|
      { id: account.id, name: account.name }
    end
  end

  def catalog_prices
    client.list_prices.data.filter_map do |price|
      next unless price.active

      {
        id: price.id,
        product_id: price.product,
        product_name: product_names[price.product] || price.nickname,
        unit_amount: price.unit_amount,
        currency: price.currency,
        recurring_interval: price.recurring&.interval
      }
    end
  end

  # Resolved for the whole page up front: a lookup inside the row loop would
  # either run a query per invoice or memoize on the first customer alone.
  def load_account_names(invoices)
    @account_names = Account.where(stripe_customer_id: invoices.filter_map(&:customer).uniq)
                            .pluck(:stripe_customer_id, :name).to_h
  end

  # What each line of the invoice is charging for.
  #
  # In this API version the price hangs off `pricing.price_details`, not
  # `line.price` — the same move that took `current_period_end` to the
  # subscription item. The line description is the fallback: it is what Stripe
  # itself prints on the invoice when the product is gone from the catalog.
  def invoice_products(invoice)
    lines = invoice.try(:lines)&.data || []

    lines.filter_map do |line|
      product_id = line.try(:pricing)&.price_details&.product
      product_names[product_id] || line.try(:description).presence
    end.uniq
  end

  # One catalog fetch per page, indexed by id — the invoice only carries the
  # product id, never its name.
  def product_names
    @product_names ||= client.list_products.data.to_h { |product| [product.id, product.name] }
  end

  def serialize(invoice)
    {
      id: invoice.id,
      number: invoice.number,
      status: invoice.status,
      customer_id: invoice.customer,
      account_name: @account_names[invoice.customer],
      customer_name: invoice.customer_name,
      amount_due: invoice.amount_due,
      amount_paid: invoice.amount_paid,
      currency: invoice.currency,
      due_date: invoice.due_date,
      created: invoice.created,
      hosted_invoice_url: invoice.hosted_invoice_url,
      invoice_pdf: invoice.invoice_pdf,
      products: invoice_products(invoice),
      # Present only on invoices written off from this screen; invoices settled
      # inside Stripe (card, boleto) legitimately have no origin of ours.
      paid_via: invoice.metadata&.[](Integrations::Stripe::Client::PAID_VIA_METADATA_KEY)
    }
  end
end
