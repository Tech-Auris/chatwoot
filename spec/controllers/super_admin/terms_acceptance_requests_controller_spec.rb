require 'rails_helper'

RSpec.describe 'Super Admin Terms Acceptance Requests', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:terms_version) { create(:terms_version, document_date: Date.new(2026, 9, 3)) }
  let(:account) { create(:account) }
  let(:manager) { create(:user, account: account) }
  let(:manager_au) { account.account_users.find_by(user: manager).tap { |au| au.update!(role: :manager) } }

  before { sign_in(super_admin, scope: :super_admin) }

  describe 'GET /super_admin/terms_acceptance_requests' do
    it 'renders the list page' do
      get '/super_admin/terms_acceptance_requests'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('TermsAcceptanceRequestsIndex')
    end

    it 'returns the campaigns with a signed/total rollup' do
      campaign = create(:terms_acceptance_request, terms_version: terms_version, created_by: super_admin)
      create(:terms_acceptance, terms_acceptance_request: campaign, terms_version: terms_version,
                                account: account, account_user: manager_au, kind: :update, required: true, status: :pending)

      get '/super_admin/terms_acceptance_requests/data'

      row = response.parsed_body['requests'].find { |r| r['id'] == campaign.id }
      expect(row).to include('kind' => 'update', 'signed_count' => 0, 'total_count' => 1)
    end
  end

  describe 'POST /super_admin/terms_acceptance_requests/preview' do
    it 'returns the fetched version content and extracted document date' do
      stub_request(:get, 'https://www.auris.ia.br/termos-de-uso').to_return(
        status: 200,
        body: '<html><body><p>Última atualização: 3 de Set de 2026.</p><p>Cláusula.</p></body></html>'
      )

      post '/super_admin/terms_acceptance_requests/preview'

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('document_date' => '2026-09-03')
      expect(response.parsed_body['content']).to include('Cláusula')
    end

    it 'reports a fetch error without raising' do
      stub_request(:get, 'https://www.auris.ia.br/termos-de-uso').to_return(status: 503)

      post '/super_admin/terms_acceptance_requests/preview'

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to match(/HTTP 503/)
    end
  end

  describe 'GET /super_admin/terms_acceptance_requests/manager_roster' do
    it 'lists accounts that have at least one manager' do
      manager_au
      other_account = create(:account) # no managers — should not appear

      get '/super_admin/terms_acceptance_requests/manager_roster'

      account_ids = response.parsed_body['accounts'].pluck('account_id')
      expect(account_ids).to include(account.id)
      expect(account_ids).not_to include(other_account.id)
    end
  end

  describe 'POST /super_admin/terms_acceptance_requests' do
    it 'fans the campaign out into acceptances + an OpsNotif' do
      manager_au

      request_count = TermsAcceptanceRequest.count
      acceptance_count = TermsAcceptance.count
      notification_count = OperationsNotification.count

      post '/super_admin/terms_acceptance_requests',
           params: { campaign: { terms_version_id: terms_version.id,
                                 document_date: '2026-09-03',
                                 deadline_at: 7.days.from_now.iso8601,
                                 required_signers_by_account: { account.id.to_s => [manager_au.id.to_s] } } }

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include('acceptance_count' => 1)
      expect(TermsAcceptanceRequest.count - request_count).to eq(1)
      expect(TermsAcceptance.count - acceptance_count).to eq(1)
      expect(OperationsNotification.count - notification_count).to eq(1)
    end

    it 'reports a validation error without persisting' do
      post '/super_admin/terms_acceptance_requests',
           params: { campaign: { terms_version_id: terms_version.id,
                                 document_date: '2026-09-03',
                                 deadline_at: 12.hours.from_now.iso8601,
                                 required_signers_by_account: { account.id.to_s => [manager_au.id.to_s] } } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(TermsAcceptanceRequest.count).to eq(0)
    end
  end

  describe 'GET /super_admin/terms_acceptance_requests/:id/report' do
    it 'returns a per-account rollup with each signer' do
      campaign = create(:terms_acceptance_request, terms_version: terms_version, created_by: super_admin)
      create(:terms_acceptance, terms_acceptance_request: campaign, terms_version: terms_version,
                                account: account, account_user: manager_au, kind: :update, required: true, status: :pending)

      get "/super_admin/terms_acceptance_requests/#{campaign.id}/report"

      account_row = response.parsed_body['accounts'].first
      expect(account_row).to include('account_id' => account.id)
      expect(account_row['signers'].first).to include('user_email' => manager.email, 'required' => true, 'status' => 'pending')
    end
  end
end
