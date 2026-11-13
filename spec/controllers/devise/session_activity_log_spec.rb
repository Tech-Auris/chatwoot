require 'rails_helper'

RSpec.describe 'Session activity log', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, password: 'Password1!', account: account) }

  it 'logs the sign in' do
    post new_user_session_url, params: { email: user.email, password: 'Password1!' }, as: :json

    log = ActivityLog.find_by!(action: 'sign_in')
    expect(log).to have_attributes(account_id: account.id, auditable_type: 'User', auditable_id: user.id,
                                   actor_type: 'User', actor_id: user.id, source: 'login')
  end

  it 'logs the sign out' do
    delete destroy_user_session_url, headers: user.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    log = ActivityLog.find_by!(action: 'sign_out')
    expect(log).to have_attributes(account_id: account.id, actor_id: user.id, source: 'login')
  end
end
