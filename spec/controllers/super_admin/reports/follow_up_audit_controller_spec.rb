require 'rails_helper'

RSpec.describe 'Super Admin FUP audit report', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account, name: 'Leger') }
  let(:conversation) { create(:conversation, account: account) }

  it 'redirects unauthenticated requests' do
    get '/super_admin/reports/follow_up_audit'
    expect(response).to have_http_status(:redirect)
  end

  it 'renders the Vue mount when authenticated' do
    sign_in(super_admin, scope: :super_admin)
    get '/super_admin/reports/follow_up_audit'

    expect(response).to have_http_status(:success)
    expect(response.body).to include('FollowUpAuditIndex')
  end

  describe 'GET /super_admin/reports/follow_up_audit/data' do
    before do
      account.update!(settings: account.settings.merge('follow_up' => { 'steps' => [240, 480] }))
      create(:follow_up, conversation: conversation, run_id: 'a', step: 1, delivery_status: :sent, outcome: :reengaged)
        .update!(processed_at: 4.seconds.from_now)
      create(:follow_up, conversation: conversation, run_id: 'a', step: 2, delivery_status: :failed, error_message: 'Template not found')
      create(:follow_up, conversation: conversation, run_id: 'b', step: 1, created_at: 10.minutes.ago)
      create(:follow_up, run_id: 'old', created_at: 3.days.ago)
      sign_in(super_admin, scope: :super_admin)
    end

    it 'sums the period, per account, and lists failures and stuck FUPs' do
      get '/super_admin/reports/follow_up_audit/data', as: :json

      body = response.parsed_body
      expect(body['totals']).to include('total' => 3, 'accounts' => 1, 'failed' => 1, 'stuck' => 1,
                                        'conversations' => 1, 'reengaged_conversations' => 1)
      expect(body['totals']['avg_seconds']).to be_within(1).of(2)
      expect(body['totals']['max_seconds']).to be_within(1).of(4)
      expect(body['accounts'].first).to include('account_name' => 'Leger', 'steps' => [240, 480], 'total' => 3, 'failed' => 1)
      expect(body['issues'].pluck('delivery_status')).to contain_exactly('failed', 'pending')
      expect(body['issues'].pluck('error_message')).to include('Template not found')
    end

    it 'widens the period and filters by delivery status' do
      get '/super_admin/reports/follow_up_audit/data', params: { period: '7d', delivery: 'failed' }, as: :json

      expect(response.parsed_body['totals']).to include('total' => 1, 'failed' => 1)
    end
  end
end
