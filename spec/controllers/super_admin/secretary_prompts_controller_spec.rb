require 'rails_helper'

RSpec.describe 'Super Admin secretary prompts', type: :request do
  let(:super_admin) { create(:super_admin) }
  let!(:prompt) { create(:secretary_prompt) }

  before { sign_in(super_admin, scope: :super_admin) }

  it 'lists the prompts' do
    get '/super_admin/secretary_prompts'

    expect(response.body).to include(prompt.core_behavior)
  end

  it 'edits a prompt in wide textareas' do
    get "/super_admin/secretary_prompts/#{prompt.id}/edit"

    expect(Nokogiri::HTML(response.body).at_css('textarea#secretary_prompt_medical_compliance')).to be_present

    patch "/super_admin/secretary_prompts/#{prompt.id}", params: { secretary_prompt: { medical_compliance: 'Nunca prescreva.' } }

    expect(prompt.reload.medical_compliance).to eq('Nunca prescreva.')
  end
end
