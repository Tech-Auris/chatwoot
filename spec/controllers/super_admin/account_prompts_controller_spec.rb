require 'rails_helper'

RSpec.describe 'Super Admin account prompts', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account, name: 'Recepção') }
  let!(:other_inbox) { create(:inbox, account: account) }

  before { sign_in(super_admin, scope: :super_admin) }

  it "shows the account's prompts on the account page, with a link to add one" do
    general = create(:account_prompt, account: account)
    specific = create(:account_prompt, :specific, account: account, name: 'Unidade Centro', inbox_ids: [inbox.id])

    get "/super_admin/accounts/#{account.id}"

    expect(response.body).to include("/super_admin/account_prompts/#{general.id}/edit")
    expect(response.body).to include("/super_admin/account_prompts/#{specific.id}/edit")
    expect(response.body.index('Geral')).to be < response.body.index('Unidade Centro')
    expect(response.body).to include("/super_admin/account_prompts/new?account_id=#{account.id}")
  end

  it "lists only the account's inboxes in the form opened from the account page, named Geral first" do
    foreign = create(:inbox, name: 'Caixa de outra conta')

    get '/super_admin/account_prompts/new', params: { account_id: account.id }

    expect(response.body).to include('Recepção')
    expect(response.body).not_to include(foreign.name)
    expect(response.body).to include('value="Geral"')
  end

  it 'lists the prompts of every account' do
    create(:account_prompt, account: account)

    get '/super_admin/account_prompts'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(account.name)
  end

  it 'creates the general prompt and goes back to the account page' do
    post '/super_admin/account_prompts', params: {
      account_prompt: { account_id: account.id, name: 'Geral', inbox_ids: [''], ai_prompt_system_message: 'Prompt geral' }
    }

    expect(response).to redirect_to("/super_admin/accounts/#{account.id}")
    expect(account.account_prompts.sole).to have_attributes(name: 'Geral', inbox_ids: [])
  end

  it 'refuses a specific prompt before the general one' do
    post '/super_admin/account_prompts', params: {
      account_prompt: { account_id: account.id, name: 'Específico 1', inbox_ids: [inbox.id.to_s], ai_prompt_system_message: 'Texto' }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.account_prompts).to be_empty
  end

  it 'creates a specific prompt once the general one exists' do
    create(:account_prompt, account: account)

    post '/super_admin/account_prompts', params: {
      account_prompt: { account_id: account.id, name: 'Específico 1', inbox_ids: ['', inbox.id.to_s, other_inbox.id.to_s],
                        ai_prompt_system_message: 'Texto' }
    }

    expect(account.account_prompts.specific.sole).to have_attributes(inbox_ids: [inbox.id, other_inbox.id].sort)
  end

  it 'keeps the general prompt when deleting it while there are specific ones' do
    general = create(:account_prompt, account: account)
    create(:account_prompt, :specific, account: account, inbox_ids: [inbox.id])

    delete "/super_admin/account_prompts/#{general.id}"

    expect(response).to redirect_to("/super_admin/accounts/#{account.id}")
    expect(flash[:error]).to include('específicos')
    expect(general.reload).to be_persisted
  end
end
