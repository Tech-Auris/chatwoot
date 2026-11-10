require 'rails_helper'

RSpec.describe 'Super Admin commercial discounts', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:base) { '/super_admin/commercial/discounts' }
  let(:stripe_client) { instance_double(Integrations::Stripe::Client, configured?: true) }

  def stripe_product(id:, name:, recurring: nil)
    Struct.new(:id, :name, :default_price).new(id, name, Struct.new(:recurring).new(recurring))
  end

  before do
    sign_in(super_admin, scope: :super_admin)
    allow(Integrations::Stripe::Client).to receive(:new).and_return(stripe_client)
    allow(stripe_client).to receive(:list_products).and_return(
      Struct.new(:data).new([stripe_product(id: 'prod_setup', name: 'Implantação'),
                             stripe_product(id: 'prod_plan', name: 'Plataforma Auris', recurring: { interval: 'month' })])
    )
  end

  it 'renders the page' do
    get base

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('CommercialDiscounts')
  end

  it 'lists every discount and only the one-off products' do
    create(:sales_discount, name: 'Antigo', active: false)

    get "#{base}/data", as: :json

    expect(response.parsed_body['discounts'].pluck('name', 'active')).to eq([['Antigo', false]])
    expect(response.parsed_body['products']).to eq([{ 'id' => 'prod_setup', 'name' => 'Implantação' }])
  end

  it 'creates a discount on specific products' do
    post base, params: { discount: { name: 'Isenção implantação', percent: 100, stripe_product_ids: ['prod_setup'] } }, as: :json

    expect(response).to have_http_status(:created)
    expect(SalesDiscount.last).to have_attributes(name: 'Isenção implantação', stripe_product_ids: ['prod_setup'], active: true)
  end

  it 'edits and turns a discount off' do
    discount = create(:sales_discount)

    patch "#{base}/#{discount.id}", params: { discount: { percent: 7, active: false } }, as: :json

    expect(discount.reload).to have_attributes(percent: 7, active: false)
  end

  it 'refuses a discount without a percent' do
    post base, params: { discount: { name: 'Sem valor' } }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to be_present
  end

  it 'is open to a sales-only admin' do
    sign_in(create(:super_admin, super_admin_role: SuperAdmin::COMMERCIAL_ROLE), scope: :super_admin)

    get "#{base}/data", as: :json

    expect(response).to have_http_status(:ok)
  end
end
