require 'rails_helper'

# A dashboard session lasts 7 days and ends after 12 hours without activity;
# either way the token stops working and the dashboard goes to the login page.
RSpec.describe 'Session expiry', type: :request do
  let(:user) { create(:user, account: create(:account)) }
  let(:headers) { user.create_new_auth_token }
  let!(:session) { user.user_sessions.create!(client_id: headers['client'], last_activity_at: Time.current) }

  it 'issues tokens that expire in 7 days' do
    expect(headers['expiry'].to_i).to be_within(5).of(7.days.from_now.to_i)
  end

  it 'keeps the session while it is used within 12 hours' do
    session.update!(last_activity_at: 11.hours.ago)

    get '/auth/validate_token', headers: headers

    expect(response).to have_http_status(:success)
  end

  it 'ends the session after 12 hours without activity and revokes its token' do
    session.update!(last_activity_at: 13.hours.ago)

    get '/auth/validate_token', headers: headers

    expect(response).to have_http_status(:unauthorized)
    expect(user.reload.tokens).not_to have_key(headers['client'])
    expect(user.user_sessions).to be_empty
  end

  it 'keeps a token that has no tracked session' do
    session.destroy!

    get '/auth/validate_token', headers: headers

    expect(response).to have_http_status(:success)
  end

  it 'ends the session once the token expires, even with recent activity' do
    travel 7.days + 1.minute do
      session.update!(last_activity_at: Time.current)

      get '/auth/validate_token', headers: headers

      expect(response).to have_http_status(:unauthorized)
    end
  end

  it 'leaves API access tokens alone' do
    session.update!(last_activity_at: 13.hours.ago)

    get '/api/v1/profile', headers: { api_access_token: user.access_token.token }

    expect(response).to have_http_status(:success)
  end
end
