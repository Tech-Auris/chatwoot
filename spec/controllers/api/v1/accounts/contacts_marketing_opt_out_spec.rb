require 'rails_helper'

RSpec.describe 'POST /api/v1/accounts/:account_id/contacts/:id/marketing_opt_out', type: :request do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:agent) { create(:user, account: account, role: :agent, name: 'Rafaela') }
  let(:ai_user) { create(:user, account: account, role: :agent, name: 'IA | Auris') }

  def toggle(user, params)
    post "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/marketing_opt_out",
         params: params, headers: user.create_new_auth_token, as: :json
  end

  it 'lets an agent turn it on, as a manual opt-out' do
    toggle(agent, { enabled: true })

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['payload']).to include('marketing_opt_out' => true, 'marketing_opt_out_source' => 'manual')
  end

  it 'lets the AI turn it on, with the AI as the source' do
    toggle(ai_user, { enabled: true, source: 'ai' })

    expect(contact.reload).to have_attributes(marketing_opt_out: true, marketing_opt_out_source: 'ai')
  end

  it 'lets an agent turn it off' do
    contact.opt_out!(source: 'meta')

    toggle(agent, { enabled: false })

    expect(response).to have_http_status(:success)
    expect(contact.reload.marketing_opt_out).to be false
  end

  it 'refuses the AI turning it off' do
    contact.opt_out!(source: 'meta')

    toggle(ai_user, { enabled: false })

    expect(response).to have_http_status(:forbidden)
    expect(contact.reload.marketing_opt_out).to be true
  end

  it 'refuses a bot turning it off' do
    contact.opt_out!(source: 'meta')
    bot = create(:agent_bot, account: account)

    post "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/marketing_opt_out",
         params: { enabled: false }, headers: { api_access_token: bot.access_token.token }, as: :json

    expect(contact.reload.marketing_opt_out).to be true
  end

  it 'is not changed through the regular contact update' do
    contact.opt_out!(source: 'meta')

    patch "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
          params: { marketing_opt_out: false }, headers: agent.create_new_auth_token, as: :json

    expect(contact.reload.marketing_opt_out).to be true
  end
end
