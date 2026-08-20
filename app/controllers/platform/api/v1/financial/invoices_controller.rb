# Invoice issuing for automation (n8n and friends), authenticated by a platform
# app token — the same credential the rest of the platform API uses.
#
# Exists so the monthly token billing can run without anybody opening the super
# admin: the caller sends the usage per account and gets back one result per
# customer, saying which invoices were issued and which were not.
class Platform::Api::V1::Financial::InvoicesController < PlatformController
  # Unlike the resource endpoints of this API, billing is instance-wide rather
  # than scoped to a permissible account, so there is no per-resource check to
  # run — holding the platform token is the authorization.
  skip_before_action :set_resource, raise: false
  skip_before_action :validate_platform_app_permissible, raise: false

  rescue_from Integrations::Stripe::Client::Unauthorized do |e|
    render json: { error: "Stripe credential rejected: #{e.message}" }, status: :unauthorized
  end

  rescue_from Integrations::Stripe::Client::ProviderUnavailable do |e|
    render json: { error: "Stripe unavailable: #{e.message}" }, status: :bad_gateway
  end

  rescue_from Financial::TokenBillingService::MissingPrices, Integrations::Stripe::Client::InvalidRequest do |e|
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Prices the run without touching Stripe, so an automation can check the
  # total before committing to it — the same reconciliation the screen offers.
  def preview
    render json: token_service.preview(usage_rows)
  end

  # Issues one invoice per account of the payload.
  def create
    results = token_service.perform(
      usage_rows,
      description: params[:description],
      days_until_due: params[:days_until_due],
      period: params[:period]
    )

    render json: { results: results, issued_count: results.count { |row| row[:status] == 'issued' },
                   prices_used: token_service.resolved_prices }, status: :created
  end

  private

  def token_service
    @token_service ||= Financial::TokenBillingService.new(prices: price_params)
  end

  # Prices may come in the request or, when omitted, from what the finance team
  # last chose on the screen — so a monthly automation does not carry a copy of
  # the price ids that silently goes stale.
  def price_params
    Financial::TokenBillingService::CATEGORIES.index_with do |category|
      params.dig(:prices, category).presence ||
        GlobalConfig.get(SuperAdmin::Financial::TokenBillingsController::PRICE_CONFIG_KEYS[category])[
          SuperAdmin::Financial::TokenBillingsController::PRICE_CONFIG_KEYS[category]
        ]
    end
  end

  def usage_rows
    Array(params[:usage]).map do |row|
      { account_id: row[:account_id].to_i, account_name: row[:account_name],
        text: row[:text].to_i, media: row[:media].to_i, audio: row[:audio].to_i }
    end
  end
end
