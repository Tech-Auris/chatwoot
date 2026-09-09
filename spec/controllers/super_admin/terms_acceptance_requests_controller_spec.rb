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
    it 'lists every account with the managers it has' do
      manager_au
      other_account = create(:account, name: 'Sem gerente') # no managers

      get '/super_admin/terms_acceptance_requests/manager_roster'

      rows = response.parsed_body['accounts']
      expect(rows.pluck('account_id')).to include(account.id, other_account.id)
      account_row = rows.find { |r| r['account_id'] == account.id }
      other_row = rows.find { |r| r['account_id'] == other_account.id }
      expect(account_row['managers'].length).to eq(1)
      # Accounts without any manager come with an empty list so the wizard
      # can render a warning row saying the account will be skipped.
      expect(other_row['managers']).to eq([])
    end

    # A suspended account is not on the roster — the campaign has nothing
    # to reach on it, so listing it (even as "sem gerente") would only be
    # noise for the operator.
    it 'skips suspended accounts entirely' do
      manager_au
      dropped = create(:account, name: 'Suspensa', status: :suspended)

      get '/super_admin/terms_acceptance_requests/manager_roster'

      account_ids = response.parsed_body['accounts'].pluck('account_id')
      expect(account_ids).not_to include(dropped.id)
    end

    # Internal Auris users are not customer managers; asking them to sign a
    # customer's terms would misplace the audit trail. Excluded from the
    # picker even when their account_user role is `manager` on a customer
    # account.
    it 'excludes internal Auris team members from the manager list' do
      manager_au
      internal = create(:user, account: account, email: 'suporte@agenteauris.com.br')
      account.account_users.find_by(user: internal).update!(role: :manager)
      internal_alt = create(:user, account: account, email: 'tech@auris.com.br')
      account.account_users.find_by(user: internal_alt).update!(role: :manager)

      get '/super_admin/terms_acceptance_requests/manager_roster'

      row = response.parsed_body['accounts'].find { |r| r['account_id'] == account.id }
      emails = row['managers'].pluck('email')
      expect(emails).to include(manager.email)
      expect(emails).not_to include('suporte@agenteauris.com.br', 'tech@auris.com.br')
    end
  end

  describe 'POST /super_admin/terms_acceptance_requests/:id/cancel_account' do
    it 'cancels the acceptances of the account only, keeping the campaign open' do
      other_account = create(:account)
      other_manager = create(:user, account: other_account)
      other_au = other_account.account_users.find_by(user: other_manager).tap { |au| au.update!(role: :manager) }

      campaign = create(:terms_acceptance_request, terms_version: terms_version, created_by: super_admin)
      create(:terms_acceptance, terms_acceptance_request: campaign, terms_version: terms_version,
                                account: account, account_user: manager_au, kind: :update,
                                required: true, status: :pending, deadline_at: campaign.deadline_at)
      create(:terms_acceptance, terms_acceptance_request: campaign, terms_version: terms_version,
                                account: other_account, account_user: other_au, kind: :update,
                                required: true, status: :pending, deadline_at: campaign.deadline_at)

      post "/super_admin/terms_acceptance_requests/#{campaign.id}/cancel_account",
           params: { account_id: account.id }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('cancelled_count' => 1)
      expect(campaign.terms_acceptances.where(account_id: account.id).pluck(:status)).to all(eq('cancelled'))
      expect(campaign.terms_acceptances.where(account_id: other_account.id).pluck(:status)).to all(eq('pending'))
      expect(campaign.reload.status).to eq('open')
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
      # Two OpsNotifs land per campaign: one for managers (subject=campaign)
      # and one info notice for agents (plain, no subject).
      expect(OperationsNotification.count - notification_count).to eq(2)
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

  describe 'DELETE /super_admin/terms_acceptance_requests/:id' do
    it 'cancels the campaign and its pending acceptances' do
      campaign = create(:terms_acceptance_request, terms_version: terms_version, created_by: super_admin)
      create(:terms_acceptance, terms_acceptance_request: campaign, terms_version: terms_version,
                                account: account, account_user: manager_au, kind: :update,
                                required: true, status: :pending, deadline_at: campaign.deadline_at)

      delete "/super_admin/terms_acceptance_requests/#{campaign.id}"

      expect(response).to have_http_status(:ok)
      expect(campaign.reload.status).to eq('closed')
      expect(campaign.terms_acceptances.status_pending.count).to eq(0)
      expect(campaign.terms_acceptances.status_cancelled.count).to eq(1)
    end
  end

  # A duplicate document_date almost always means the super_admin forgot the
  # previous campaign is still open. The wizard's second submit with
  # `force: true` cancels the previous and creates the new one.
  describe 'POST create with a duplicate document_date' do
    let!(:existing) do
      create(:terms_acceptance_request, terms_version: terms_version, created_by: super_admin,
                                        document_date: Date.new(2026, 9, 3), status: :open)
    end

    it 'refuses with 409 and surfaces the existing campaign' do
      manager_au

      post '/super_admin/terms_acceptance_requests',
           params: { campaign: { terms_version_id: terms_version.id,
                                 document_date: '2026-09-03',
                                 deadline_at: 7.days.from_now.iso8601,
                                 required_signers_by_account: { account.id.to_s => [manager_au.id.to_s] } } }

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body.dig('existing_campaign', 'id')).to eq(existing.id)
    end

    it 'cancels the previous and creates the new one when force is true' do
      manager_au

      post '/super_admin/terms_acceptance_requests',
           params: { force: true,
                     campaign: { terms_version_id: terms_version.id,
                                 document_date: '2026-09-03',
                                 deadline_at: 7.days.from_now.iso8601,
                                 required_signers_by_account: { account.id.to_s => [manager_au.id.to_s] } } }

      expect(response).to have_http_status(:created)
      expect(existing.reload.status).to eq('closed')
      expect(TermsAcceptanceRequest.status_open.count).to eq(1)
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
