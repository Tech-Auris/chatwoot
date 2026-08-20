# Discounts available to be applied on a subscription or on an invoice.
#
# A coupon restricted to products (`applies_to`) is how a discount reaches one
# line of a subscription instead of the whole bill — which is how the team
# discounts a single product today.
class SuperAdmin::Financial::CouponsController < SuperAdmin::ApplicationController
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
    render json: { coupons: client.list_coupons.data.map { |coupon| serialize(coupon) }, products: catalog_products }
  end

  def create
    coupon = client.create_coupon(coupon_params)

    render json: { coupon: serialize(coupon) }, status: :created
  end

  # Stripe has no archived state for a coupon. Deleting stops it from being
  # applied again; whoever already redeemed it keeps the discount.
  def destroy
    client.delete_coupon(params[:id])

    head :ok
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

  def coupon_params
    {
      name: params.require(:name),
      percent_off: params[:percent_off],
      # Typed in reais, charged in cents.
      amount_off: params[:amount_off].present? ? (params[:amount_off].to_f * 100).round : nil,
      duration: params[:duration],
      duration_in_months: params[:duration_in_months],
      product_ids: Array(params[:product_ids]).compact_blank,
      max_redemptions: params[:max_redemptions]
    }
  end

  def catalog_products
    client.list_products.data.map { |product| { id: product.id, name: product.name } }
  end

  def serialize(coupon)
    {
      id: coupon.id,
      name: coupon.name,
      percent_off: coupon.percent_off,
      amount_off: coupon.amount_off,
      currency: coupon.currency,
      duration: coupon.duration,
      duration_in_months: coupon.duration_in_months,
      times_redeemed: coupon.times_redeemed,
      max_redemptions: coupon.max_redemptions,
      valid: coupon.valid,
      product_ids: coupon.applies_to&.products || []
    }
  end
end
