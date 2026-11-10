# Commercial → Descontos: the discounts the plan builder offers the seller.
#
# `index` renders the Vue shell; the rest is JSON for it. Discounts are never
# deleted — a proposal keeps its own copy of what it applied, and turning one
# off is what takes it out of the plan builder.
class SuperAdmin::Commercial::DiscountsController < SuperAdmin::ApplicationController
  rescue_from Integrations::Stripe::Client::Unauthorized do |e|
    render json: { error: "Credencial do Stripe inválida: #{e.message}" }, status: :unauthorized
  end

  rescue_from Integrations::Stripe::Client::ProviderUnavailable do |e|
    render json: { error: "Stripe indisponível: #{e.message}" }, status: :bad_gateway
  end

  def index; end

  def data
    render json: { discounts: SalesDiscount.ordered.map { |discount| serialize(discount) }, products: one_off_products }
  end

  def create
    discount = SalesDiscount.new(discount_params)
    discount.position = SalesDiscount.maximum(:position).to_i + 1
    save(discount, :created)
  end

  def update
    discount = SalesDiscount.find(params[:id])
    discount.assign_attributes(discount_params)
    save(discount, :ok)
  end

  private

  def save(discount, status)
    if discount.save
      render json: { discount: serialize(discount) }, status: status
    else
      render json: { error: discount.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  def discount_params
    params.require(:discount).permit(:name, :percent, :expires_with_reservation, :active, stripe_product_ids: [])
  end

  def serialize(discount)
    discount.snapshot.merge(id: discount.id, active: discount.active)
  end

  # A discount on products only reaches one-off lines (implantação,
  # integrações): the CRM reads the implementation value as the one-off lines
  # minus the waivers, so a cut on the subscription would land there.
  def one_off_products
    client = Integrations::Stripe::Client.new
    return [] unless client.configured?

    client.list_products(active: true).data.filter_map do |product|
      next if product.default_price.blank? || product.default_price.recurring.present?

      { id: product.id, name: product.name }
    end
  end
end
