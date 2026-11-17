require 'rails_helper'

RSpec.describe 'Super Admin secretary confirmations', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let!(:confirmation) { create(:secretary_confirmation, account: account, calendar_id: 'agenda-da-conta') }

  before { sign_in(super_admin, scope: :super_admin) }

  it "lists an account's reminder settings" do
    create(:secretary_confirmation, calendar_id: 'agenda-de-outra-conta')

    get '/super_admin/secretary_confirmations', params: { search: "account:#{account.id}" }

    expect(response.body).to include('agenda-da-conta')
    expect(response.body).not_to include('agenda-de-outra-conta')
  end

  it 'creates a row, a blank version meaning the V2 flow' do
    post '/super_admin/secretary_confirmations', params: {
      secretary_confirmation: { account_id: account.id, versao_workflow: '', calendar_id: 'nova', message: 'Lembrete', message_2h: '' }
    }

    expect(account.secretary_confirmations.find_by(calendar_id: 'nova')).to have_attributes(versao_workflow: nil, message: 'Lembrete')
  end

  it 'edits a row' do
    patch "/super_admin/secretary_confirmations/#{confirmation.id}", params: { secretary_confirmation: { message_30m: 'Em 30 minutos' } }

    expect(confirmation.reload.message_30m).to eq('Em 30 minutos')
  end
end
