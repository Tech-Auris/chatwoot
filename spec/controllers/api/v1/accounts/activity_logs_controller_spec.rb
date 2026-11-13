require 'rails_helper'

RSpec.describe 'Activity Logs API', type: :request do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/activity_logs" }

  def create_log(**attributes)
    ActivityLog.create!({ account_id: account.id, auditable_type: 'Contact', auditable_id: 1, auditable_label: 'Maria',
                          action: 'update', actor_type: 'User', actor_id: admin.id, actor_label: admin.name,
                          source: 'dashboard', audited_changes: { 'name' => %w[Ana Maria] } }.merge(attributes))
  end

  before { ActivityLog.delete_all }

  describe 'GET /activity_logs' do
    it 'refuses agents' do
      get base_url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'lists the account logs, newest first, with the filter options' do
      older = create_log(created_at: 2.days.ago)
      newer = create_log(auditable_type: 'Label', created_at: 1.hour.ago)
      ActivityLog.create!(account_id: create(:account).id, auditable_type: 'Label', action: 'create', actor_type: 'System', source: 'job')

      get base_url, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['payload'].pluck('id')).to eq([newer.id, older.id])
      expect(body['payload'].first['changed_fields']).to eq(['name'])
      expect(body['meta']).to include('count' => 2, 'auditable_types' => %w[Contact Label])
    end

    it 'filters by period, user, type, action, origin and record' do
      match = create_log(auditable_id: 4512, source: 'api', action: 'destroy')
      create_log(source: 'api', action: 'update')
      create_log(created_at: 10.days.ago, auditable_id: 4512, source: 'api', action: 'destroy')
      create_log(actor_id: agent.id, auditable_id: 4512, source: 'api', action: 'destroy')

      get base_url,
          params: { since: 1.day.ago.iso8601, until: 1.minute.from_now.iso8601, user_id: admin.id, auditable_type: 'Contact',
                    log_action: 'destroy', source: 'api', q: 'contato 4512' },
          headers: admin.create_new_auth_token

      expect(response.parsed_body['payload'].pluck('id')).to eq([match.id])
    end

    it 'searches the record name' do
      match = create_log(auditable_label: 'Clínica Sorriso')
      create_log(auditable_label: 'Outro')

      get base_url, params: { q: 'sorriso' }, headers: admin.create_new_auth_token

      expect(response.parsed_body['payload'].pluck('id')).to eq([match.id])
    end
  end

  describe 'GET /activity_logs/:id' do
    it 'returns the changes and the history of the record' do
      first = create_log(created_at: 1.day.ago)
      last = create_log
      create_log(auditable_id: 2)

      get "#{base_url}/#{last.id}", headers: admin.create_new_auth_token, as: :json

      body = response.parsed_body
      expect(body['audited_changes']).to eq('name' => %w[Ana Maria])
      expect(body['history'].pluck('id')).to eq([last.id, first.id])
    end

    it 'does not show another account log' do
      other = ActivityLog.create!(account_id: create(:account).id, auditable_type: 'Label', action: 'create', actor_type: 'System', source: 'job')

      get "#{base_url}/#{other.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /activity_logs/export' do
    it 'downloads the filtered logs as CSV without secret values' do
      create_log(audited_changes: { 'name' => %w[Ana Maria], 'secret' => [ActivityLog::FILTERED, ActivityLog::FILTERED] })
      create_log(source: 'api', auditable_label: 'Via API')

      get "#{base_url}/export", params: { source: 'dashboard' }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.headers['Content-Type']).to include('text/csv')
      csv = CSV.parse(response.body.delete_prefix(ActivityLogs::ExportService::BOM), headers: true)
      expect(csv.size).to eq(1)
      expect(csv.first[8]).to include('name: Ana → Maria')
      expect(csv.first[8]).not_to include(ActivityLog::FILTERED)
    end

    it 'refuses agents' do
      get "#{base_url}/export", headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'context of changes made through the API' do
    let(:contact) { create(:contact, account: account) }

    it 'logs the token owner with origin api' do
      patch "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
            params: { name: 'Via n8n' }, headers: { api_access_token: admin.access_token.token }, as: :json

      log = ActivityLog.find_by!(auditable_type: 'Contact', auditable_id: contact.id, action: 'update')
      expect(log).to have_attributes(actor_type: 'User', actor_id: admin.id, source: 'api')
      expect(log.ip_address).to be_present
    end

    it 'logs the signed in user with origin dashboard' do
      patch "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
            params: { name: 'Pelo painel' }, headers: admin.create_new_auth_token, as: :json

      log = ActivityLog.find_by!(auditable_type: 'Contact', auditable_id: contact.id, action: 'update')
      expect(log).to have_attributes(actor_type: 'User', actor_id: admin.id, source: 'dashboard')
    end
  end
end
