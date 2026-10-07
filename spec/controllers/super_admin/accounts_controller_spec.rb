require 'rails_helper'

RSpec.describe 'Super Admin accounts API', type: :request do
  include ActiveJob::TestHelper

  let!(:super_admin) { create(:super_admin) }
  let!(:account) { create(:account) }

  describe 'GET /super_admin/accounts' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get '/super_admin/accounts'
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated user' do
      it 'shows the list of accounts' do
        sign_in(super_admin, scope: :super_admin)
        get '/super_admin/accounts'
        expect(response).to have_http_status(:success)
        expect(response.body).to include('New account')
        expect(response.body).to include(account.name)
      end

      it 'renders the new account page, where the secretary waits for the account to exist' do
        sign_in(super_admin, scope: :super_admin)

        get '/super_admin/accounts/new'

        expect(response).to have_http_status(:success)
        expect(response.body).to include('Disponível depois de criar a conta')
      end

      it 'starts a new account with the funnel on and reports in Brasília time' do
        sign_in(super_admin, scope: :super_admin)

        get '/super_admin/accounts/new'

        page = Nokogiri::HTML(response.body)
        expect(page.at_css('input[type=checkbox][name="auris_settings[funnel_enabled]"]')['checked']).to eq('checked')
        expect(page.at_css('select[name="account[reporting_timezone]"] option[selected]')['value']).to eq('America/Sao_Paulo')
      end

      it 'shows the secretary section on the edit page' do
        sign_in(super_admin, scope: :super_admin)

        get "/super_admin/accounts/#{account.id}/edit"

        expect(response.body).to include('AccountSecretary', 'secretary')
      end

      it 'shows the secretary version and filters by it' do
        version = create(:secretary_version, name: 'v3.2')
        on_version = create(:account, name: 'Clinica Na Versao')
        create(:account_secretary, account: on_version, secretary_version: version)
        sign_in(super_admin, scope: :super_admin)

        get '/super_admin/accounts', params: { search: "secretaria:#{version.id}" }
        expect(response.body).to include('Clinica Na Versao', 'v3.2', 'Secretary Version')
        expect(response.body).not_to include('Secretary Version Name')
        expect(response.body).not_to include(account.name)

        get '/super_admin/accounts', params: { search: 'secretaria:nenhuma' }
        expect(response.body).to include(account.name)
        expect(response.body).not_to include('Clinica Na Versao')
      end

      # Real prod incident: typing any text in the Super Admin accounts
      # search box returned 500 ("column accounts.reporting_timezone does
      # not exist"). `reporting_timezone` is a `store_accessor` on the
      # jsonb `settings` column, not a real DB column — Administrate was
      # trying to auto-search it because `Field::Select` is searchable
      # by default. The dashboard entry now sets `searchable: false`.
      it 'returns a successful response when a search term is provided' do
        sign_in(super_admin, scope: :super_admin)
        get '/super_admin/accounts', params: { search: 'harmonize' }
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'POST /super_admin/accounts/{account_id}/reset_cache' do
    before do
      create(:label, account: account)
      create(:inbox, account: account)
      create(:team, account: account)
    end

    after do
      Conversations::UnreadCounts::Store.clear_account!(account.id)
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/super_admin/accounts/#{account.id}/reset_cache"
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated user' do
      it 'shows the list of accounts' do
        expect(account.cache_keys.keys).to contain_exactly(:inbox, :label, :team)
        sign_in(super_admin, scope: :super_admin)

        now_timestamp = (Time.now.utc.to_f * 1000).to_i
        post "/super_admin/accounts/#{account.id}/reset_cache"
        expect(response).to have_http_status(:redirect)
        expect(flash[:notice]).to eq('Cache keys cleared')

        range = now_timestamp..(now_timestamp + 10_000)
        expect(account.reload.cache_keys.values.all? { |v| range.cover?(v.to_i) }).to be(true)
      end
    end
  end

  describe 'POST /super_admin/accounts/{account_id}/provision_simulator_inbox' do
    # Prod accounts don't auto-provision a Simulador inbox (that's env_test's
    # after_commit). Super Admin gets a manual button for QA / demos.
    let!(:prod_account) { create(:account, environment: :production) }

    before { sign_in(super_admin, scope: :super_admin) }

    it 'creates a Simulador channel + inbox and stamps simulator_inbox_id when the account has none' do
      expect(prod_account.simulator_inbox_id).to be_nil

      expect do
        post "/super_admin/accounts/#{prod_account.id}/provision_simulator_inbox"
      end.to change(Channel::Simulator, :count).by(1)

      prod_account.reload
      expect(prod_account.simulator_inbox_id).to be_present
      expect(Inbox.find(prod_account.simulator_inbox_id).name).to eq('Simulador')
      expect(flash[:notice]).to eq('Simulador inbox provisioned.')
    end

    it 'is a no-op when the account already has a live Simulador inbox' do
      existing_channel = Channel::Simulator.create!(account: prod_account)
      existing_inbox = prod_account.inboxes.create!(name: 'Simulador', channel: existing_channel)
      prod_account.update!(simulator_inbox_id: existing_inbox.id)

      expect do
        post "/super_admin/accounts/#{prod_account.id}/provision_simulator_inbox"
      end.not_to change(Channel::Simulator, :count)

      expect(prod_account.reload.simulator_inbox_id).to eq(existing_inbox.id)
      expect(flash[:notice]).to eq('Simulador inbox already exists — no action taken.')
    end

    it 'reprovisions when the cached simulator_inbox_id is stale (inbox deleted)' do
      prod_account.update!(simulator_inbox_id: 999_999_999)

      expect do
        post "/super_admin/accounts/#{prod_account.id}/provision_simulator_inbox"
      end.to change(Channel::Simulator, :count).by(1)

      expect(prod_account.reload.simulator_inbox_id).not_to eq(999_999_999)
    end
  end

  describe 'PUT /super_admin/accounts/{account_id} (Secretária section)' do
    let!(:reception) { create(:inbox, account: account) }
    let!(:sales) { create(:inbox, account: account) }
    let(:version) { create(:secretary_version) }
    let(:testing) { create(:secretary_version, status: :testing) }

    before { sign_in(super_admin, scope: :super_admin) }

    it 'saves the secretary with the account, in the same submit' do
      put "/super_admin/accounts/#{account.id}", params: {
        account: { name: 'Clinica Nova' },
        secretary: { secretary_version_id: version.id, simulator_version_id: testing.id, inbox_ids: ['', reception.id] }
      }

      expect(response).to have_http_status(:redirect)
      expect(account.reload.name).to eq('Clinica Nova')
      expect(account.account_secretary).to have_attributes(secretary_version: version, simulator_version: testing)
      expect(account.account_secretary.secret).to be_present
      expect(reception.reload.secretary_enabled).to be(true)
      expect(sales.reload.secretary_enabled).to be(false)
    end

    it 'turns every inbox off when the list is cleared' do
      reception.update!(secretary_enabled: true)

      put "/super_admin/accounts/#{account.id}",
          params: { account: { name: account.name }, secretary: { secretary_version_id: version.id, inbox_ids: [''] } }

      expect(reception.reload.secretary_enabled).to be(false)
    end

    it 'leaves the secretary untouched when the section was not posted' do
      reception.update!(secretary_enabled: true)

      put "/super_admin/accounts/#{account.id}", params: { account: { name: account.name } }

      expect(reception.reload.secretary_enabled).to be(true)
    end

    it 'refuses a testing version for the account' do
      put "/super_admin/accounts/#{account.id}",
          params: { account: { name: account.name }, secretary: { secretary_version_id: testing.id, inbox_ids: [''] } }

      expect(flash[:alert]).to be_present
      expect(account.reload.account_secretary&.secretary_version).to be_nil
    end
  end

  describe 'PUT /super_admin/accounts/{account_id} (Auris settings section)' do
    let(:params) do
      {
        account: { name: account.name },
        auris_settings: {
          funnel_enabled: '1',
          ai_status_uses_attribute: '1',
          multi_language_ai: '1'
        }
      }
    end

    before { sign_in(super_admin, scope: :super_admin) }

    it 'persists Funnel and AI status toggles to their dedicated columns' do
      account.update!(funnel_enabled: false, ai_status_uses_attribute: false)

      put "/super_admin/accounts/#{account.id}", params: params

      expect(response).to have_http_status(:redirect)
      account.reload
      expect(account.funnel_enabled).to be(true)
      expect(account.ai_status_uses_attribute).to be(true)
    end

    it 'flips the multi_language_ai column' do
      expect(account.multi_language_ai).to be(false)

      put "/super_admin/accounts/#{account.id}", params: params

      expect(response).to have_http_status(:redirect)
      expect(account.reload.multi_language_ai).to be(true)
    end

    it 'turns settings back off when the checkboxes are submitted unchecked' do
      account.update!(funnel_enabled: true, ai_status_uses_attribute: true, multi_language_ai: true)

      put "/super_admin/accounts/#{account.id}",
          params: params.merge(auris_settings: {
                                 funnel_enabled: '0',
                                 ai_status_uses_attribute: '0',
                                 multi_language_ai: '0'
                               })

      account.reload
      expect(account.funnel_enabled).to be(false)
      expect(account.ai_status_uses_attribute).to be(false)
      expect(account.multi_language_ai).to be(false)
    end
  end

  describe 'PUT /super_admin/accounts/{account_id} (reporting_timezone)' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'persists the reporting_timezone selection from the form' do
      expect(account.reporting_timezone).to be_nil

      put "/super_admin/accounts/#{account.id}",
          params: { account: { name: account.name, reporting_timezone: 'America/Mexico_City' } }

      expect(response).to have_http_status(:redirect)
      expect(account.reload.reporting_timezone).to eq('America/Mexico_City')
    end

    it 'clears the override when the blank option is submitted' do
      account.update!(reporting_timezone: 'America/Mexico_City')

      put "/super_admin/accounts/#{account.id}",
          params: { account: { name: account.name, reporting_timezone: '' } }

      expect(account.reload.reporting_timezone).to be_blank
    end

    it 'rejects an invalid timezone string' do
      put "/super_admin/accounts/#{account.id}",
          params: { account: { name: account.name, reporting_timezone: 'Mars/Olympus_Mons' } }

      # Administrate re-renders the edit form with 422 on validation failure.
      expect(response).to have_http_status(:unprocessable_content)
      expect(account.reload.reporting_timezone).to be_blank
    end

    it 'renders the timezone select on the edit form' do
      get "/super_admin/accounts/#{account.id}/edit"

      expect(response.body).to include('account[reporting_timezone]')
      expect(response.body).to include('America/Mexico_City')
    end
  end

  describe 'DELETE /super_admin/accounts/{account_id}' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/super_admin/accounts/#{account.id}"
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated user' do
      it 'Deletes the account' do
        total_accounts = Account.count
        sign_in(super_admin, scope: :super_admin)

        perform_enqueued_jobs(only: DeleteObjectJob) do
          delete "/super_admin/accounts/#{account.id}"
        end

        expect(Account.count).to eq(total_accounts - 1)
      end
    end
  end

  describe 'PUT /super_admin/accounts/{account_id} (environment toggle)' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'flips the environment to production when submitted' do
      account.update!(environment: :test)

      put "/super_admin/accounts/#{account.id}",
          params: { account: { name: account.name, environment: 'production' } }

      expect(response).to have_http_status(:redirect)
      expect(account.reload.environment).to eq('production')
    end

    it 'flips the environment to test when submitted' do
      account.update!(environment: :production)

      put "/super_admin/accounts/#{account.id}",
          params: { account: { name: account.name, environment: 'test' } }

      expect(account.reload.environment).to eq('test')
    end

    it 'renders the EnvironmentField dropdown with the confirmation script on edit' do
      get "/super_admin/accounts/#{account.id}/edit"

      expect(response.body).to include('data-environment-select="true"')
      expect(response.body).to include('AMBIENTE DE TESTE')
    end
  end
end
