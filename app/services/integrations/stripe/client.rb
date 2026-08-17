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

  private

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
