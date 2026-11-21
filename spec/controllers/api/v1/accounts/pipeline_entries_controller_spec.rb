require 'rails_helper'

RSpec.describe 'Pipeline entries API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:pipeline) { create(:pipeline, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:base_url) { "/api/v1/accounts/#{account.id}" }

  describe 'POST /pipelines/:id/entries' do
    it 'adds the contact once, on the first stage, as manual by the agent' do
      2.times do
        post "#{base_url}/pipelines/#{pipeline.id}/entries", params: { contact_id: contact.id }, headers: agent.create_new_auth_token, as: :json
      end

      expect(response).to have_http_status(:success)
      entry = response.parsed_body['payload']
      expect(entry).to include('pipeline_stage_id' => pipeline.first_open_stage.id, 'source' => 'manual')
      expect(entry['added_by']).to eq('id' => agent.id, 'name' => agent.name)
      expect(pipeline.entries.count).to eq(1)
    end

    it 'does not add a contact of another account' do
      post "#{base_url}/pipelines/#{pipeline.id}/entries", params: { contact_id: create(:contact).id }, headers: agent.create_new_auth_token,
                                                           as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'PATCH /pipeline_entries/:id/move' do
    let(:entry) { create(:pipeline_entry, pipeline: pipeline, contact: contact) }

    it 'moves the entry' do
      retorno = pipeline.stages.find_by(name: 'Retorno')

      patch "#{base_url}/pipeline_entries/#{entry.id}/move", params: { pipeline_stage_id: retorno.id }, headers: agent.create_new_auth_token,
                                                             as: :json

      expect(response.parsed_body.dig('payload', 'pipeline_stage_id')).to eq(retorno.id)
    end

    it 'asks the loss reason for Perdido' do
      patch "#{base_url}/pipeline_entries/#{entry.id}/move", params: { pipeline_stage_id: pipeline.stages.lost.first.id },
                                                             headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it 'removes the contact from the pipeline' do
    entry = create(:pipeline_entry, pipeline: pipeline, contact: contact)

    delete "#{base_url}/pipeline_entries/#{entry.id}", headers: agent.create_new_auth_token, as: :json

    expect(PipelineEntry.exists?(entry.id)).to be false
  end

  describe 'GET /contacts/:id/pipeline_entries' do
    it 'lists one entry per pipeline, the one in progress first' do
      won = create(:pipeline_entry, pipeline: pipeline, contact: contact, stage: pipeline.stages.won.first, closed_at: 1.day.ago)
      current = create(:pipeline_entry, pipeline: pipeline, contact: contact)
      other = create(:pipeline_entry, pipeline: create(:pipeline, account: account), contact: contact)
      create(:pipeline_entry, pipeline: create(:pipeline, account: account, archived_at: Time.current), contact: contact)

      get "#{base_url}/contacts/#{contact.id}/pipeline_entries", headers: agent.create_new_auth_token, as: :json

      ids = response.parsed_body['payload'].pluck('id')
      expect(ids).to contain_exactly(current.id, other.id)
      expect(ids).not_to include(won.id)
    end
  end
end
