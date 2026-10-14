require 'rails_helper'

RSpec.describe 'Super Admin AI providers and models', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:provider) { create(:ai_provider, name: 'OpenAI') }

  before { sign_in(super_admin, scope: :super_admin) }

  it 'lists the providers with their models' do
    create(:ai_model, ai_provider: provider, name: 'gpt-5.1')

    get '/super_admin/ai_providers'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('OpenAI')
  end

  it 'registers a new model under a provider' do
    post '/super_admin/ai_models', params: {
      ai_model: { ai_provider_id: provider.id, name: 'gpt-6.2', key: 'openai_next', model_id: 'gpt-6.2', status: 'active' }
    }

    expect(AiModel.find_by(key: 'openai_next')).to have_attributes(ai_provider: provider, model_id: 'gpt-6.2')
  end

  it 'lists the models' do
    create(:ai_model, ai_provider: provider, name: 'gpt-5.1')

    get '/super_admin/ai_models'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('gpt-5.1')
  end
end
