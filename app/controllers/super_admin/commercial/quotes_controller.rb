# Where the sales team builds a proposal during a meeting with a prospect.
#
# The prospect comes from the ClickUp pipeline (the deal lives there), the
# catalogue comes from Stripe, and what results is a draft proposal — the
# reservation and the public link come in the next step.
class SuperAdmin::Commercial::QuotesController < SuperAdmin::ApplicationController
  rescue_from Integrations::Stripe::Client::Unauthorized, Integrations::Clickup::Client::Unauthorized do |e|
    render json: { error: "Credencial rejeitada: #{e.message}" }, status: :unauthorized
  end

  rescue_from Integrations::Stripe::Client::ProviderUnavailable, Integrations::Clickup::Client::ProviderUnavailable do |e|
    render json: { error: "Serviço indisponível: #{e.message}" }, status: :bad_gateway
  end

  rescue_from Sales::ClickupProspectSearchService::NotConfigured, Integrations::Stripe::Client::InvalidRequest do |e|
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def index; end

  # Catalogue and coupons for the cart. Prospects are not sent here: the list is
  # searched as the operator types.
  def data
    render json: { prices: catalog_prices, coupons: available_coupons,
                   meeting_discount_percent: Sales::QuoteCalculatorService::MEETING_DISCOUNT_PERCENT }
  end

  def prospects
    render json: { prospects: Sales::ClickupProspectSearchService.new.search(params[:q]) }
  end

  # Prices the cart without persisting anything, so the seller sees the total
  # move as the meeting goes.
  def preview
    result = calculator.perform

    render json: { subtotal: result.subtotal, discount: result.discount, total: result.total, summary: result.summary }
  end

  # Holds the proposal until a date and mirrors it onto the ClickUp task. The
  # same action renews an existing reservation — the seller pushing the deadline
  # is the same operation as setting it the first time.
  def reserve
    result = Sales::ReserveQuoteService.new(
      quote: quote, reserved_until: parsed_reserved_until, user: current_super_admin
    ).perform

    render json: {
      quote: serialize(result.quote),
      clickup_synced: result.clickup_synced,
      clickup_error: result.clickup_error
    }
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def create
    quote = SalesQuote.new(quote_attributes)
    quote.items = item_records

    apply_totals(quote)
    quote.save!
    quote.events.create!(event: 'created', user: current_super_admin, metadata: { items: quote.items.size })

    render json: { quote: serialize(quote) }, status: :created
  end

  private

  def quote
    @quote ||= SalesQuote.find(params[:id])
  end

  def parsed_reserved_until
    value = params.require(:reserved_until)
    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def stripe_client
    @stripe_client ||= Integrations::Stripe::Client.new
  end

  def calculator
    Sales::QuoteCalculatorService.new(
      items: submitted_items,
      meeting_discount: ActiveModel::Type::Boolean.new.cast(params[:meeting_discount]),
      coupon: selected_coupon
    )
  end

  def submitted_items
    Array(params[:items]).map do |item|
      { unit_amount: item[:unit_amount].to_i, quantity: item[:quantity].presence&.to_i || 1 }
    end
  end

  def item_records
    Array(params[:items]).map do |item|
      SalesQuoteItem.new(
        stripe_price_id: item[:stripe_price_id],
        stripe_product_id: item[:stripe_product_id],
        name: item[:name],
        unit_amount: item[:unit_amount].to_i,
        quantity: item[:quantity].presence&.to_i || 1,
        recurring_interval: item[:recurring_interval],
        kind: item[:kind].presence || :plan
      )
    end
  end

  def quote_attributes
    prospect = Sales::ClickupProspectSearchService.new.find(params.require(:clickup_task_id)) || {}

    {
      seller: current_super_admin,
      clickup_task_id: params.require(:clickup_task_id),
      clickup_status: prospect[:status],
      clickup_status_synced_at: Time.current,
      # The task title is the person the seller talked to; the clinic is a custom
      # field that is usually still empty at this point and gets filled by the
      # prospect on the public form.
      prospect_name: prospect[:name],
      company_name: prospect[:clinic_name],
      prospect_email: prospect[:email],
      prospect_phone: prospect[:phone],
      meeting_discount: ActiveModel::Type::Boolean.new.cast(params[:meeting_discount]),
      coupon_id: params[:coupon_id].presence,
      billing_cycle: billing_cycle_from_items,
      status: :draft
    }
  end

  # The plan item carries the period the whole proposal is on. Checkout
  # routes card payments by this — Stripe for monthly (a subscription
  # lives where the recurrence lives), AsaaS for semi/annual (paid in
  # instalments). Nil when the cart has no plan yet, which validation
  # will refuse on save; unknown periods are dropped so a stray
  # `billing_period` never blows up the create with an enum error.
  ALLOWED_BILLING_CYCLES = SalesQuote.billing_cycles.keys.freeze
  def billing_cycle_from_items
    plan_item = Array(params[:items]).find { |item| (item[:kind].presence || 'plan') == 'plan' }
    period = plan_item&.[](:billing_period).to_s
    ALLOWED_BILLING_CYCLES.include?(period) ? period : nil
  end

  # Totals are frozen on the proposal: the catalogue moves, and what the
  # prospect was shown has to survive that.
  def apply_totals(quote)
    result = calculator.perform
    quote.subtotal_amount = result.subtotal
    quote.discount_amount = result.discount
    quote.total_amount = result.total
    quote.discount_summary = result.summary
  end

  def selected_coupon
    return nil if params[:coupon_id].blank?

    available_coupons.find { |coupon| coupon[:id] == params[:coupon_id] }
  end

  # What the seller can put in the cart: the prices of products that are still
  # on sale, most used first — archived products keep their prices active in
  # Stripe, so filtering the price alone let a retired plan be sold again.
  def catalog_prices
    products = stripe_client.list_products(active: true).data.index_by(&:id)
    usage = price_usage_counts

    prices = stripe_client.list_prices.data.filter_map do |price|
      product = products[price.product]
      next if !price.active || product.nil?

      serialize_price(price, product, usage[price.id].to_i)
    end

    prices.sort_by { |price| [-price[:usage_count], price[:product_name].to_s.downcase] }
  end

  def serialize_price(price, product, usage_count)
    {
      id: price.id, product_id: product.id, product_name: product.name.presence || price.nickname,
      unit_amount: price.unit_amount, currency: price.currency,
      recurring_interval: price.recurring&.interval,
      billing_period: billing_period_of(price),
      category: category_of(product, price),
      usage_count: usage_count
    }
  end

  # How often each price was actually sold. The catalogue grows and the team
  # sells a handful of combinations, so what has been sold before is the best
  # order we have for what comes first.
  def price_usage_counts
    SalesQuoteItem.group(:stripe_price_id).count
  end

  # Stripe describes a semiannual plan as six monthly intervals, so the period
  # only reads right once the count is taken with the interval.
  def billing_period_of(price)
    return 'one_off' if price.recurring.blank?

    months = price.recurring.interval == 'year' ? price.recurring.interval_count * 12 : price.recurring.interval_count

    case months
    when 1 then 'monthly'
    when 6 then 'semiannual'
    when 12 then 'annual'
    else 'other'
    end
  end

  # The subscription itself against everything sold beside it. A product says
  # so through `auris_category` in Stripe; without it, a recurring price is the
  # plan and a one-off is an extra, which is what the cart has always assumed.
  def category_of(product, price)
    declared = product.metadata&.[]('auris_category').presence
    return declared if %w[plan addon].include?(declared)

    price.recurring.present? ? 'plan' : 'addon'
  end

  def available_coupons
    @available_coupons ||= stripe_client.list_coupons.data.filter_map do |coupon|
      next unless coupon.valid

      { id: coupon.id, name: coupon.name, percent_off: coupon.percent_off, amount_off: coupon.amount_off, currency: coupon.currency }
    end
  end

  def serialize(quote)
    {
      id: quote.id, public_token: quote.public_token, access_code: quote.access_code,
      public_url: public_url_for(quote), qr_code: qr_code_for(quote),
      reserved_until: quote.reserved_until, phone_last4: quote.verification_phone_last4,
      prospect_name: quote.prospect_name, subtotal_amount: quote.subtotal_amount,
      discount_amount: quote.discount_amount, total_amount: quote.total_amount,
      discount_summary: quote.discount_summary, status: quote.status
    }
  end

  def public_url_for(quote)
    sales_proposal_url(quote.public_token, host: ENV.fetch('FRONTEND_URL', request.base_url))
  end

  # Rendered here rather than in the browser: the seller shares the screen with
  # the customer during the meeting, and the QR has to be there on load.
  def qr_code_for(quote)
    svg = RQRCode::QRCode.new(public_url_for(quote)).as_svg(module_size: 4, standalone: true, use_path: true)
    "data:image/svg+xml;base64,#{Base64.strict_encode64(svg)}"
  end
end
