# Products screen of the Financeiro section. Stripe is the source of truth:
# nothing is mirrored locally, every read hits the API so the screen can never
# drift from what someone changed on the Stripe dashboard.
#
# `index` renders the Vue shell; every other action is called by it over JSON.
class SuperAdmin::Financial::ProductsController < SuperAdmin::ApplicationController
  DEFAULT_CURRENCY = 'brl'.freeze

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
    render json: { products: client.list_products.data.map { |product| serialize(product) } }
  end

  def create
    product = client.create_product(
      name: product_params[:name],
      description: product_params[:description],
      active: true
    )
    create_initial_price(product.id)

    render json: { product: serialize(product) }, status: :created
  end

  def update
    render json: { product: serialize(client.update_product(params[:id], update_attributes)) }
  end

  # Archive, not delete: Stripe refuses to delete a product that has prices,
  # and a deleted product would break the invoices referencing it.
  def destroy
    render json: { product: serialize(client.archive_product(params[:id])) }
  end

  def prices
    render json: { price: serialize_price(build_price(params[:id])) }, status: :created
  end

  private

  def client
    @client ||= Integrations::Stripe::Client.new
  end

  def ensure_configured
    return if client.configured?

    render json: { error: 'Stripe não está configurado. Salve a Stripe Secret Key em Settings → Stripe.' },
           status: :unprocessable_entity
  end

  def product_params
    params.require(:product).permit(:name, :description, :active)
  end

  def price_params
    params.require(:price).permit(:unit_amount, :currency, :recurring_interval)
  end

  def update_attributes
    attributes = { name: product_params[:name], description: product_params[:description] }.compact
    attributes[:active] = ActiveModel::Type::Boolean.new.cast(product_params[:active]) unless product_params[:active].nil?
    attributes
  end

  # A product created with a price in the same form saves the operator a second
  # round trip. The price is optional — products without one are valid in
  # Stripe and useful while the catalog is being drafted.
  def create_initial_price(product_id)
    return if params.dig(:price, :unit_amount).blank?

    build_price(product_id)
  end

  def build_price(product_id)
    client.create_price(
      product_id: product_id,
      unit_amount: price_params[:unit_amount].to_i,
      currency: price_params[:currency].presence || DEFAULT_CURRENCY,
      recurring_interval: price_params[:recurring_interval].presence
    )
  end

  # Prices come from a single list call grouped by product, so rendering N
  # products stays one API round trip instead of N+1.
  def prices_by_product
    @prices_by_product ||= client.list_prices.data.group_by(&:product)
  end

  def serialize(product)
    {
      id: product.id,
      name: product.name,
      description: product.description,
      active: product.active,
      created: product.created,
      prices: prices_by_product.fetch(product.id, []).map { |price| serialize_price(price) }
    }
  end

  def serialize_price(price)
    return nil if price.blank?

    {
      id: price.id,
      unit_amount: price.unit_amount,
      currency: price.currency,
      active: price.active,
      recurring_interval: price.recurring&.interval
    }
  end
end
