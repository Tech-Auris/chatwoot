require 'rails_helper'

RSpec.describe 'Pipelines API', type: :request do
  let(:account) { create(:account, locale: :pt_BR) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/pipelines" }

  describe 'POST /pipelines' do
    let(:payload) do
      { name: 'Protocolo Emagrecimento', stages: [{ name: 'Acompanhamento D+10', color: '#3b82f6' }, { name: 'Retorno D+30', color: '#10b981' }] }
    end

    it 'creates the pipeline with its stages plus Ganho and Perdido' do
      post base_url, params: payload, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      stages = response.parsed_body.dig('payload', 'stages')
      expect(stages.pluck('name')).to eq(['Acompanhamento D+10', 'Retorno D+30', 'Ganho', 'Perdido'])
      expect(stages.pluck('kind')).to eq(%w[open open won lost])
    end

    it 'is not allowed to agents' do
      post base_url, params: payload, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(account.pipelines).to be_empty
    end
  end

  describe 'GET /pipelines' do
    it 'lists the active pipelines with their contacts in progress, never another account' do
      pipeline = create(:pipeline, account: account)
      create(:pipeline_entry, pipeline: pipeline)
      create(:pipeline, account: account, archived_at: Time.current)
      create(:pipeline)

      get base_url, headers: agent.create_new_auth_token, as: :json

      payload = response.parsed_body['payload']
      expect(payload.pluck('id')).to eq([pipeline.id])
      expect(payload.first['entries_count']).to eq(1)
    end
  end

  describe 'archive and delete' do
    let!(:pipeline) { create(:pipeline, account: account) }
    let!(:entry) { create(:pipeline_entry, pipeline: pipeline) }

    it 'archives keeping the contacts, and reactivates' do
      post "#{base_url}/#{pipeline.id}/archive", headers: admin.create_new_auth_token, as: :json
      expect(pipeline.reload).to be_archived
      expect(entry.reload).to be_persisted

      post "#{base_url}/#{pipeline.id}/unarchive", headers: admin.create_new_auth_token, as: :json
      expect(pipeline.reload).not_to be_archived
    end

    it 'deletes the pipeline with everything in it' do
      delete "#{base_url}/#{pipeline.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(PipelineEntry.exists?(entry.id)).to be false
    end

    it 'lists the automations that use the pipeline before deleting it' do
      create(:automation_rule, account: account, name: 'Retorno D+30',
                               actions: [{ action_name: 'move_to_pipeline_stage', action_params: [pipeline.first_open_stage.id] }])
      create(:automation_rule, account: account, name: 'Outra')

      get "#{base_url}/#{pipeline.id}/automations", headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload'].pluck('name')).to eq(['Retorno D+30'])
    end

    it 'does not show a pipeline of another account' do
      other = create(:pipeline)

      get "#{base_url}/#{other.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /pipelines/:id/board' do
    let(:pipeline) { create(:pipeline, account: account) }

    it 'pages the entries of each stage with the latest conversation of the contact' do
      entries = create_list(:pipeline_entry, 3, pipeline: pipeline)
      conversation = create(:conversation, account: account, contact: entries.last.contact)

      get "#{base_url}/#{pipeline.id}/board", params: { per_page: 2 }, headers: agent.create_new_auth_token

      stage = response.parsed_body.dig('payload', 'stages').first
      expect(stage).to include('count' => 3, 'has_more' => true)
      expect(stage['entries'].size).to eq(2)
      card = stage['entries'].first
      expect(card['latest_conversation']).to eq('id' => conversation.display_id, 'status' => 'open')
    end

    it 'walks the next page of a stage' do
      create_list(:pipeline_entry, 3, pipeline: pipeline)

      get "#{base_url}/#{pipeline.id}/stages/#{pipeline.first_open_stage.id}/entries", params: { per_page: 2, page: 2 },
                                                                                       headers: agent.create_new_auth_token

      expect(response.parsed_body.dig('payload', 'entries').size).to eq(1)
      expect(response.parsed_body.dig('payload', 'meta', 'has_more')).to be false
    end

    it 'hides the closed passes when asked' do
      create(:pipeline_entry, pipeline: pipeline, stage: pipeline.stages.won.first, closed_at: Time.current)

      get "#{base_url}/#{pipeline.id}/board", params: { hide_closed: true }, headers: agent.create_new_auth_token

      expect(response.parsed_body.dig('payload', 'stages').sum { |stage| stage['count'] }).to eq(0)
    end
  end

  describe 'stages' do
    let(:pipeline) { create(:pipeline, account: account) }
    let(:acompanhamento) { pipeline.stages.find_by(name: 'Acompanhamento') }
    let(:retorno) { pipeline.stages.find_by(name: 'Retorno') }

    it 'adds a stage before Ganho and Perdido' do
      post "#{base_url}/#{pipeline.id}/stages", params: { name: 'Pós D+60', color: '#f59e0b' }, headers: admin.create_new_auth_token, as: :json

      expect(pipeline.stages.reload.map(&:name)).to eq(['Acompanhamento', 'Retorno', 'Pós D+60', 'Ganho', 'Perdido'])
    end

    it 'reorders the clinic stages' do
      post "#{base_url}/#{pipeline.id}/stages/reorder", params: { ids: [retorno.id, acompanhamento.id] },
                                                        headers: admin.create_new_auth_token, as: :json

      expect(pipeline.stages.reload.map(&:name)).to eq(%w[Retorno Acompanhamento Ganho Perdido])
    end

    it 'deletes a stage moving its contacts' do
      entry = create(:pipeline_entry, pipeline: pipeline, stage: acompanhamento)

      delete "#{base_url}/#{pipeline.id}/stages/#{acompanhamento.id}", params: { move_to_stage_id: retorno.id },
                                                                       headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(entry.reload.stage).to eq(retorno)
    end

    it 'refuses to delete Perdido' do
      delete "#{base_url}/#{pipeline.id}/stages/#{pipeline.stages.lost.first.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to eq(I18n.t('pipelines.errors.closing_stage_delete'))
    end

    it 'is not configurable by agents' do
      post "#{base_url}/#{pipeline.id}/stages", params: { name: 'X', color: '#000' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
