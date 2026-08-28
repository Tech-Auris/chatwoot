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
      status: :draft
    }
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

  def catalog_prices
    product_names = stripe_client.list_products.data.to_h { |product| [product.id, product.name] }

    stripe_client.list_prices.data.filter_map do |price|
      next unless price.active

      {
        id: price.id, product_id: price.product, product_name: product_names[price.product] || price.nickname,
        unit_amount: price.unit_amount, currency: price.currency, recurring_interval: price.recurring&.interval
      }
    end
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
