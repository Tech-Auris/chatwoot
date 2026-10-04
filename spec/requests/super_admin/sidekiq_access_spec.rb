require 'rails_helper'

# Sidekiq Web lives outside the Administrate controllers, so only the route
# constraint keeps restricted super admins away from the queues.
RSpec.describe 'Sidekiq panel access', type: :request do
  it 'is open to a full super admin' do
    sign_in(create(:super_admin), scope: :super_admin)

    get '/monitoring/sidekiq'

    expect(response).to have_http_status(:success)
  end

  [SuperAdmin::FINANCIAL_ROLE, SuperAdmin::COMMERCIAL_ROLE].each do |role|
    it "is closed to a #{role}-only super admin" do
      sign_in(create(:super_admin, super_admin_role: role), scope: :super_admin)

      get '/monitoring/sidekiq'

      expect(response).not_to have_http_status(:success)
    end
  end
end
