require 'rails_helper'

RSpec.describe 'Secretary confirmations API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  def list(params, user = admin)
    get '/api/v1/secretary_confirmations', params: params, headers: user.create_new_auth_token, as: :json
  end

  it 'returns unauthorized without a token' do
    get '/api/v1/secretary_confirmations', params: { versao_workflow: '5.1' }

    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns the rows of the asked version in the Supabase row shape' do
    confirmation = create(:secretary_confirmation, account: account, inbox_id: '243', unidade_id: 0)
    create(:secretary_confirmation, account: account, versao_workflow: '3')

    list(versao_workflow: '5.1')

    expect(response.parsed_body).to contain_exactly(
      include('id' => confirmation.id.to_s, 'chatwoot_account_id' => account.id, 'cliente_id' => account.id, 'inbox_id' => '243',
              'unidade_id' => 0, 'message_2h' => '', 'message_72h' => nil, 'versao_workflow' => '5.1')
    )
  end

  it "matches the rows without a version with 'null' and filters the accounts like the V2 and V3 queries" do
    other_account = create(:account)
    create(:account_user, account: other_account, user: admin, role: :administrator)
    create(:secretary_confirmation, account: account, versao_workflow: nil)
    create(:secretary_confirmation, account: other_account, versao_workflow: '2')

    list(versao_workflow: 'null,2', except_account_id: other_account.id)
    expect(response.parsed_body.pluck('chatwoot_account_id')).to eq([account.id])

    list(versao_workflow: 'null,2', account_id: other_account.id)
    expect(response.parsed_body.pluck('chatwoot_account_id')).to eq([other_account.id])
  end

  it "doesn't return the rows of accounts the caller doesn't administer" do
    agent = create(:user, account: account, role: :agent)
    create(:secretary_confirmation, account: account)
    create(:secretary_confirmation)

    list({ versao_workflow: '5.1' }, agent)

    expect(response.parsed_body).to eq([])
  end
end
