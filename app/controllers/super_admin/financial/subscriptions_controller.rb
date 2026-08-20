# The Stripe subscriptions behind each reconciled account, and the screen that
# starts a new one.
#
# Only accounts already paired on Financeiro → Vínculos can appear here: with
# no Stripe customer there is nothing to look up. Accounts that are paired but
# have no subscription are listed on purpose — that is the list of who should
# be billed and isn't.
class SuperAdmin::Financial::SubscriptionsController < SuperAdmin::ApplicationController
  PER_PAGE = 25

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
    render json: {
      accounts: paginated_accounts.map { |account| serialize_account(account) },
      prices: billable_prices,
      coupons: available_coupons,
      meta: pagination_meta
    }
  end

  # Starts a subscription for an account already paired with a Stripe customer.
  # Billing is always by invoice — see `Integrations::Stripe::Client#create_subscription`.
  def create
    account = Account.find(params[:account_id])
    return render json: { error: 'Conta sem cliente do Stripe vinculado.' }, status: :unprocessable_entity if account.stripe_customer_id.blank?

    subscription = client.create_subscription(
      customer_id: account.stripe_customer_id,
      price_id: params.require(:price_id),
      quantity: params[:quantity].presence&.to_i || 1,
      days_until_due: params[:days_until_due].presence&.to_i || Integrations::Stripe::Client::DEFAULT_DAYS_UNTIL_DUE,
      coupon_id: params[:coupon_id].presence
    )

    render json: { subscription: serialize_subscription(subscription) }, status: :created
  end

  private

  # Only coupons Stripe still considers usable — an expired one or one past its
  # redemption limit would be refused at the worst possible moment.
  def available_coupons
    client.list_coupons.data.filter_map do |coupon|
      next unless coupon.valid

      { id: coupon.id, name: coupon.name, percent_off: coupon.percent_off,
        amount_off: coupon.amount_off, currency: coupon.currency, duration: coupon.duration }
    end
  end

  # Only recurring prices can back a subscription — a one-off price makes Stripe
  # reject the call, so it never reaches the picker. Archived prices are gone
  # from the catalog on purpose and must not be offered either.
  def billable_prices
    client.list_prices.data.filter_map do |price|
      next if price.recurring.blank? || !price.active

      {
        id: price.id,
        product_name: product_names[price.product] || price.nickname,
        unit_amount: price.unit_amount,
        currency: price.currency,
        recurring_interval: price.recurring.interval
      }
    end
  end

  def client
    @client ||= Integrations::Stripe::Client.new
  end

  def ensure_configured
    return if client.configured?

    render json: { error: 'Stripe não está configurado. Salve a Stripe Secret Key em Settings → Stripe.' },
           status: :unprocessable_entity
  end

  def paginated_accounts
    @paginated_accounts ||= begin
      scope = Account.where.not(stripe_customer_id: nil).order(:name)
      scope = scope.where('accounts.name ILIKE ?', "%#{params[:search]}%") if params[:search].present?
      scope = scope.where(id: account_ids_without_subscription) if params[:scope] == 'without_subscription'
      scope.page(params[:page] || 1).per(PER_PAGE)
    end
  end

  def account_ids_without_subscription
    Account.where.not(stripe_customer_id: nil)
           .reject { |account| subscriptions_by_customer.key?(account.stripe_customer_id) }
           .map(&:id)
  end

  # One list call for the whole account, indexed by customer, so rendering a
  # page of accounts doesn't turn into a request per row.
  def subscriptions_by_customer
    @subscriptions_by_customer ||= client.list_subscriptions.group_by(&:customer)
  end

  # Prices come inline on the subscription items, but `price.product` is just
  # an id — the catalog is fetched once to turn those into names.
  def product_names
    @product_names ||= client.list_products.data.to_h { |product| [product.id, product.name] }
  end

  def serialize_account(account)
    subscriptions = subscriptions_by_customer.fetch(account.stripe_customer_id, [])

    {
      id: account.id,
      name: account.name,
      stripe_customer_id: account.stripe_customer_id,
      subscriptions: subscriptions.map { |subscription| serialize_subscription(subscription) }
    }
  end

  def serialize_subscription(subscription)
    items = subscription.items.data

    {
      id: subscription.id,
      status: subscription.status,
      collection_method: subscription.collection_method,
      cancel_at_period_end: subscription.cancel_at_period_end,
      # `current_period_end` lives on the item in this API version, not on the
      # subscription. Every item of a subscription shares the same period, so
      # the first one answers for the whole row.
      current_period_end: items.first&.current_period_end,
      total_amount: total_amount(items),
      currency: items.first&.price&.currency,
      items: items.map { |item| serialize_item(item) }
    }
  end

  # What the customer is charged per cycle: every item's price times how many
  # of it the subscription carries.
  def total_amount(items)
    items.sum { |item| (item.price&.unit_amount || 0) * (item.quantity || 1) }
  end

  def serialize_item(item)
    price = item.price

    {
      id: item.id,
      quantity: item.quantity,
      product_name: product_names[price&.product] || price&.nickname,
      unit_amount: price&.unit_amount,
      currency: price&.currency,
      recurring_interval: price&.recurring&.interval
    }
  end

  def pagination_meta
    linked = Account.where.not(stripe_customer_id: nil)

    {
      current_page: paginated_accounts.current_page,
      total_pages: paginated_accounts.total_pages,
      total_count: paginated_accounts.total_count,
      linked_count: linked.count,
      without_subscription_count: account_ids_without_subscription.size
    }
  end
end
