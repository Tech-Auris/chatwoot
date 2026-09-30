require 'rails_helper'

RSpec.describe 'Super Admin Login events', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let(:manager) { create(:user, account: account, role: :manager, name: 'Alexandra') }
  let(:agent) { create(:user, account: account, role: :agent, name: 'Bruno') }

  def session_for(user, last_activity_at:, client_id: SecureRandom.hex(4), started_at: 50.days.ago)
    UserSession.create!(user: user, client_id: client_id, last_activity_at: last_activity_at, created_at: started_at,
                        ip_address: '177.45.46.164', browser_name: 'Chrome')
  end

  before { sign_in(super_admin, scope: :super_admin) }

  describe 'GET /super_admin/login_events/activity' do
    # A session stays valid for months: somebody working today without typing
    # a password never shows as a login, but shows here.
    it "lists who used the dashboard today, from the sessions' last activity" do
      session_for(manager, last_activity_at: 10.minutes.ago)
      session_for(manager, last_activity_at: 1.hour.ago)
      session_for(agent, last_activity_at: 3.days.ago)

      get '/super_admin/login_events/activity', as: :json

      rows = response.parsed_body['rows']
      expect(rows.pluck('user_name')).to eq(['Alexandra'])
      expect(rows.first).to include('role' => 'manager', 'sessions_count' => 2, 'ip_address' => '177.45.46.164')
    end

    it 'filters by role and period' do
      session_for(manager, last_activity_at: 10.minutes.ago)
      session_for(agent, last_activity_at: 3.days.ago)

      get '/super_admin/login_events/activity',
          params: { role: 'agent', from: 4.days.ago.iso8601, to: 2.days.ago.iso8601 }, as: :json

      expect(response.parsed_body['rows'].pluck('user_name')).to eq(['Bruno'])
    end
  end
end
