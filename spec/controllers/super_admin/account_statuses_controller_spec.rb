require 'rails_helper'

RSpec.describe 'Super Admin account statuses', type: :request do
  let(:super_admin) { create(:super_admin) }
  let!(:account_status) { create(:account_status) }

  before { sign_in(super_admin, scope: :super_admin) }

  it 'lists the statuses' do
    get '/super_admin/account_statuses'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Sem pagamento')
  end

  it 'edits the private note the secretary leaves' do
    patch "/super_admin/account_statuses/#{account_status.id}",
          params: { account_status: { private_message: 'Regularize o pagamento.', message_cooldown_minutes: 120 } }

    expect(account_status.reload).to have_attributes(private_message: 'Regularize o pagamento.', message_cooldown_minutes: 120)
  end

  it 'offers the new statuses on the account form' do
    get "/super_admin/accounts/#{create(:account).id}/edit"

    expect(response.body).to include('Sem pagamento', 'payment_pending', 'ai_disabled_with_message')
  end
end
