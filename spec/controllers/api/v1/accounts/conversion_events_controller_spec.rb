require 'rails_helper'

RSpec.describe 'Conversion Events API', type: :request do
  let!(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'GET /api/v1/accounts/{id}/conversion_events' do
    it 'refuses agents' do
      create(:conversion_event, account: account, name: 'Agendou')
      get "/api/v1/accounts/#{account.id}/conversion_events", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'lists events for administrators sorted by name' do
      create(:conversion_event, account: account, name: 'Agendou')
      create(:conversion_event, account: account, name: 'Confirmou')

      get "/api/v1/accounts/#{account.id}/conversion_events", headers: admin.create_new_auth_token, as: :json

      names = response.parsed_body['payload'].map { |e| e['name'] }
      expect(names).to eq(%w[Agendou Confirmou])
    end
  end

  describe 'POST /api/v1/accounts/{id}/conversion_events' do
    it 'creates a funnel-stage-reached event with the mapping' do
      post "/api/v1/accounts/#{account.id}/conversion_events",
           headers: admin.create_new_auth_token,
           params: {
             name: 'Agendou', trigger_type: 'funnel_stage_reached',
             trigger_config: { funnel_stage_id: 42 },
             meta_event_name: 'Schedule', google_event_name: 'book_appointment'
           },
           as: :json

      expect(response).to have_http_status(:success)
      event = account.conversion_events.last
      expect(event).to have_attributes(name: 'Agendou', trigger_type: 'funnel_stage_reached',
                                       meta_event_name: 'Schedule', google_event_name: 'book_appointment')
      expect(event.trigger_config).to eq('funnel_stage_id' => 42)
    end

    it 'validates the trigger_config against the trigger_type' do
      post "/api/v1/accounts/#{account.id}/conversion_events",
           headers: admin.create_new_auth_token,
           params: {
             name: 'Broken', trigger_type: 'funnel_stage_reached', trigger_config: {},
             meta_event_name: 'Schedule'
           },
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'rejects an event that targets neither provider' do
      post "/api/v1/accounts/#{account.id}/conversion_events",
           headers: admin.create_new_auth_token,
           params: {
             name: 'Silent', trigger_type: 'automation_action', trigger_config: {}
           },
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'PATCH /api/v1/accounts/{id}/conversion_events/{id}' do
    let!(:event) { create(:conversion_event, account: account, name: 'Old') }

    it 'updates the trigger and event names' do
      patch "/api/v1/accounts/#{account.id}/conversion_events/#{event.id}",
            headers: admin.create_new_auth_token,
            params: { name: 'New', google_event_name: 'book_appointment' },
            as: :json

      expect(event.reload).to have_attributes(name: 'New', google_event_name: 'book_appointment')
    end
  end

  describe 'DELETE /api/v1/accounts/{id}/conversion_events/{id}' do
    let!(:event) { create(:conversion_event, account: account) }

    it 'destroys the event' do
      expect do
        delete "/api/v1/accounts/#{account.id}/conversion_events/#{event.id}",
               headers: admin.create_new_auth_token, as: :json
      end.to change(ConversionEvent, :count).by(-1)
    end
  end
end
