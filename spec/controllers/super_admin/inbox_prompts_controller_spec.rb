require 'rails_helper'

RSpec.describe 'Super Admin inbox prompts', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account, name: 'Recepção') }
  let!(:other_inbox) { create(:inbox, account: account) }

  before { sign_in(super_admin, scope: :super_admin) }

  it "shows the account's prompts on the account page, with a link to add one" do
    prompt = create(:inbox_prompt, account: account, inbox_ids: [inbox.id])

    get "/super_admin/accounts/#{account.id}"

    expect(response.body).to include("/super_admin/inbox_prompts/#{prompt.id}/edit")
    expect(response.body).to include("/super_admin/inbox_prompts/new?account_id=#{account.id}")
  end

  it "lists only the account's inboxes in the form opened from the account page" do
    foreign = create(:inbox, name: 'Caixa de outra conta')

    get '/super_admin/inbox_prompts/new', params: { account_id: account.id }

    expect(response.body).to include('Recepção')
    expect(response.body).not_to include(foreign.name)
  end

  it 'creates a prompt and goes back to the account page' do
    post '/super_admin/inbox_prompts', params: {
      inbox_prompt: { account_id: account.id, inbox_ids: ['', inbox.id.to_s, other_inbox.id.to_s], ai_prompt_system_message: 'Prompt novo' }
    }

    expect(response).to redirect_to("/super_admin/accounts/#{account.id}")
    expect(account.inbox_prompts.sole).to have_attributes(ai_prompt_system_message: 'Prompt novo', inbox_ids: [inbox.id, other_inbox.id].sort)
  end

  it 'refuses an inbox already in another prompt of the account' do
    create(:inbox_prompt, account: account, inbox_ids: [inbox.id])

    post '/super_admin/inbox_prompts', params: {
      inbox_prompt: { account_id: account.id, inbox_ids: [inbox.id.to_s], ai_prompt_system_message: 'Outro' }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.inbox_prompts.count).to eq(1)
  end

  it 'edits a prompt' do
    prompt = create(:inbox_prompt, account: account, inbox_ids: [inbox.id])

    patch "/super_admin/inbox_prompts/#{prompt.id}",
          params: { inbox_prompt: { inbox_ids: [other_inbox.id.to_s], ai_prompt_system_message: 'Editado' } }

    expect(prompt.reload).to have_attributes(ai_prompt_system_message: 'Editado', inbox_ids: [other_inbox.id])
  end
end
