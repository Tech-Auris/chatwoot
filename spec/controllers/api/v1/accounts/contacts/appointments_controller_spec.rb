require 'rails_helper'

RSpec.describe '/api/v1/accounts/{account.id}/contacts/:id/appointments', type: :request do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact,
                          contact_inbox: create(:contact_inbox, contact: contact, inbox: inbox))
  end
  let(:other_conversation) do
    create(:conversation, account: account, inbox: other_inbox, contact: contact,
                          contact_inbox: create(:contact_inbox, contact: contact, inbox: other_inbox))
  end
  let!(:attended) do
    create(:appointment, account: account, conversation: conversation, external_id: 'ag_1', status: :attended,
                         scheduled_for: 3.days.ago, procedure_name: 'Avaliação')
  end
  let!(:upcoming) do
    create(:appointment, account: account, conversation: other_conversation, external_id: 'ag_2',
                         scheduled_for: 2.days.from_now, professional_name: 'Dra. Ana')
  end

  before do
    create(:inbox_member, user: agent, inbox: inbox)
    attended.procedures.create!(account: account, procedure_name: 'Botox', amount_paid_cents: 450_000)
  end

  it 'returns unauthorized without a session' do
    get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/appointments"

    expect(response).to have_http_status(:unauthorized)
  end

  it 'lists every appointment of the contact, newest first, with the closed procedures' do
    get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/appointments", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    payload = response.parsed_body['payload']
    expect(payload.pluck('id')).to eq([upcoming.id, attended.id])
    expect(payload.last['procedures']).to eq([{ 'id' => nil, 'name' => 'Botox', 'amount_paid' => 4500.0 }])
  end

  it 'shows an agent only the appointments of their inboxes' do
    get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/appointments", headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body['payload'].pluck('id')).to eq([attended.id])
  end
end
