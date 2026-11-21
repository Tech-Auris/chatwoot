require 'rails_helper'

RSpec.describe 'Super admin account setup API', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:headers) { { api_access_token: super_admin.access_token.token } }
  let(:account) { create(:account, name: 'Clínica Leger', multi_language_ai: true) }

  describe 'GET /api/v1/super_admin/accounts' do
    let!(:other) { create(:account, name: 'Centrus') }

    before { account }

    it 'finds accounts by name or id' do
      get '/api/v1/super_admin/accounts', params: { q: 'leger' }, headers: headers, as: :json
      expect(response.parsed_body['payload'].pluck('id')).to eq([account.id])

      get '/api/v1/super_admin/accounts', params: { q: other.id.to_s }, headers: headers, as: :json
      expect(response.parsed_body['payload'].pluck('name')).to eq(['Centrus'])
    end

    it 'refuses administrators who are not super admins' do
      admin = create(:user, account: account, role: :administrator)

      get '/api/v1/super_admin/accounts', headers: { api_access_token: admin.access_token.token }, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET /api/v1/super_admin/accounts/:id/secretary_context' do
    let(:version) { create(:secretary_version, name: 'v3.5') }
    let(:secretary_inbox) { create(:inbox, account: account, name: 'WhatsApp Recepção', secretary_enabled: true) }

    before do
      model = create(:ai_model, name: 'gpt-5.1', ai_provider: create(:ai_provider, name: 'OpenAI'))
      create(:account_secretary, account: account, secretary_version: version, ai_model: model)
      account.update!(follow_up: { 'steps' => [30, 120],
                                   'end_flow' => { 'enabled' => true, 'summary_message' => 'Resumo: @resumo@',
                                                   'escalation_message' => 'Vou te passar para a equipe.' } })
      create(:account_prompt, account: account, ai_prompt_system_message: 'Prompt geral')
      create(:account_prompt, account: account, name: 'Específico 1', inbox_ids: [secretary_inbox.id], ai_prompt_system_message: 'Prompt da recepção')
      create(:secretary_special_scenario, account: account, name: 'reembolso')
      create(:secretary_resource, account: account, key: 'tabela_precos', idioma: 'pt-br')
      create(:secretary_confirmation, account: account, inbox_id: secretary_inbox.id.to_s, unidade_id: 2, message_96h: 'Faltam 4 dias')
      create(:secretary_confirmation_send_log, account: account, reminder_type: '24h')
      create(:secretary_confirmation_send_log, account: account, reminder_type: '2h', sent_at: 10.days.ago)
    end

    def context_body
      get "/api/v1/super_admin/accounts/#{account.id}/secretary_context", headers: headers, as: :json
      expect(response).to have_http_status(:success)
      response.parsed_body
    end

    it 'returns the account flags and the secretary setup to a super admin who is not a member' do
      body = context_body

      expect(body['account']['flags']).to include('multi_language_ai' => true, 'ai_status_uses_attribute' => true)
      expect(body['secretary']).to include('version' => 'v3.5', 'simulator_version' => nil, 'ai_provider' => 'OpenAI',
                                           'ai_model' => 'gpt-5.1', 'secret_present' => true,
                                           'enabled_inboxes' => [{ 'id' => secretary_inbox.id, 'name' => 'WhatsApp Recepção' }])
    end

    it 'returns the follow-up, marking the end wait that comes from the installation default' do
      expect(context_body['follow_up']).to eq('steps' => [30, 120], 'escalate_on_end' => true, 'end_wait_is_default' => true,
                                              'end_wait_minutes' => Account.default_follow_up_end_wait_minutes,
                                              'summary_message' => 'Resumo: @resumo@',
                                              'escalation_message' => 'Vou te passar para a equipe.')
    end

    it 'returns the prompts with their inboxes, the scenarios and the resources' do
      body = context_body

      expect(body['prompts'].map { |prompt| [prompt['name'], prompt['general'], prompt['text']] })
        .to eq([['Geral', true, 'Prompt geral'], ['Específico 1', false, 'Prompt da recepção']])
      expect(body['prompts'].last['inboxes']).to eq([{ 'id' => secretary_inbox.id, 'name' => 'WhatsApp Recepção' }])
      expect(body['special_scenarios'].first).to include('name' => 'reembolso', 'instrucao' => 'Explique que o reembolso é feito pelo convênio.')
      expect(body['resources'].first).to include('key' => 'tabela_precos', 'type' => 'image', 'idioma' => 'pt-br')
    end

    it 'returns the reminders with the base message and unit, and the sends of the last 7 days' do
      confirmations = context_body['confirmations']

      expect(confirmations['reminders'].first).to include('unidade_id' => 2, 'message_96h' => 'Faltam 4 dias', 'inbox_name' => 'WhatsApp Recepção',
                                                          'message' => 'Olá {{nome}}, confirma sua consulta {{dia}} às {{hora}}?')
      expect(confirmations['sent_last_7_days']).to eq('24h' => 1)
      expect(confirmations['last_sent_at']).to be_present
    end

    it 'never returns the secret value, only whether it is filled in' do
      secret = account.account_secretary.secret
      account.account_secretary.update!(secret: nil)

      get "/api/v1/super_admin/accounts/#{account.id}/secretary_context", headers: headers, as: :json

      expect(response.parsed_body['secretary']['secret_present']).to be(false)
      expect(response.body).not_to include(secret)
    end

    it 'returns only the asked sections' do
      get "/api/v1/super_admin/accounts/#{account.id}/secretary_context", params: { sections: 'special_scenarios,bogus' },
                                                                          headers: headers, as: :json

      expect(response.parsed_body.keys).to contain_exactly('id', 'name', 'special_scenarios')
    end

    it 'refuses administrators of the account who are not super admins' do
      admin = create(:user, account: account, role: :administrator)

      get "/api/v1/super_admin/accounts/#{account.id}/secretary_context", headers: { api_access_token: admin.access_token.token }, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET /api/v1/super_admin/secretary_prompt' do
    it 'returns the global Base Prompt' do
      create(:secretary_prompt)

      get '/api/v1/super_admin/secretary_prompt', headers: headers, as: :json

      expect(response.parsed_body).to include('core_behavior' => 'Seja cordial.', 'tools_usage' => 'Use a agenda antes de confirmar horários.')
    end
  end
end
