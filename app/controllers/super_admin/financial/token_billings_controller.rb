# Monthly token billing: the finance team imports the usage spreadsheet, checks
# the totals, and only then issues the invoices.
#
# The import never bills anything. Reconciliation before issuing is the whole
# point — a batch of wrong invoices reaches real customers and cannot be
# quietly undone.
class SuperAdmin::Financial::TokenBillingsController < SuperAdmin::ApplicationController
  # Chosen prices are remembered so next month's import comes ready.
  PRICE_CONFIG_KEYS = {
    text: 'STRIPE_TOKEN_PRICE_TEXT',
    media: 'STRIPE_TOKEN_PRICE_MEDIA',
    audio: 'STRIPE_TOKEN_PRICE_AUDIO'
  }.freeze

  rescue_from Integrations::Stripe::Client::Unauthorized do |e|
    render json: { error: "Credencial do Stripe inválida: #{e.message}" }, status: :unauthorized
  end

  rescue_from Integrations::Stripe::Client::ProviderUnavailable do |e|
    render json: { error: "Stripe indisponível: #{e.message}" }, status: :bad_gateway
  end

  rescue_from Financial::TokenUsageCsvParser::InvalidFile, Financial::TokenBillingService::MissingPrices,
              Integrations::Stripe::Client::InvalidRequest do |e|
    render json: { error: e.message }, status: :unprocessable_entity
  end

  before_action :ensure_configured, except: [:index]

  def index; end

  def data
    render json: { prices: catalog_prices, selected_prices: saved_prices }
  end

  # Reads the spreadsheet and prices it. Nothing is sent to Stripe here.
  def preview
    rows = Financial::TokenUsageCsvParser.new(file: params.require(:file)).parse
    render json: service.preview(rows).merge(rows: rows)
  end

  def create
    remember_prices
    results = service.perform(
      billing_rows,
      description: params[:description],
      days_until_due: params[:days_until_due],
      period: params[:period]
    )

    render json: { results: results, issued_count: results.count { |row| row[:status] == 'issued' } }, status: :created
  end

  private

  def client
    @client ||= Integrations::Stripe::Client.new
  end

  def service
    @service ||= Financial::TokenBillingService.new(prices: price_params, client: client)
  end

  def ensure_configured
    return if client.configured?

    render json: { error: 'Stripe não está configurado. Salve a Stripe Secret Key em Settings → Stripe.' },
           status: :unprocessable_entity
  end

  def price_params
    Financial::TokenBillingService::CATEGORIES.index_with { |category| params.dig(:prices, category) }
  end

  # The rows come back from the browser exactly as the preview received them,
  # so what is billed is what the team just reconciled on screen.
  def billing_rows
    Array(params[:rows]).map do |row|
      { account_id: row[:account_id].to_i, account_name: row[:account_name],
        text: row[:text].to_i, media: row[:media].to_i, audio: row[:audio].to_i }
    end
  end

  def catalog_prices
    client.list_prices.data.filter_map do |price|
      next unless price.active

      { id: price.id, nickname: price.nickname, product_id: price.product,
        product_name: product_names[price.product], unit_amount: price.unit_amount,
        currency: price.currency,
        # A product usually carries both a one-off and a monthly price of the
        # same amount; without this the two read identically in the picker.
        recurring_interval: price.recurring&.interval }
    end
  end

  def product_names
    @product_names ||= client.list_products.data.to_h { |product| [product.id, product.name] }
  end

  def saved_prices
    PRICE_CONFIG_KEYS.transform_values { |key| GlobalConfig.get(key)[key] }
  end

  def remember_prices
    PRICE_CONFIG_KEYS.each do |category, key|
      value = params.dig(:prices, category)
      next if value.blank?

      InstallationConfig.where(name: key).first_or_initialize.update!(value: value, locked: false)
    end
    GlobalConfig.clear_cache
  end
end
