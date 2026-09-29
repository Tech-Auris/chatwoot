require 'rails_helper'

RSpec.describe 'Super Admin Commercial Settings', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account, name: 'Auris') }
  let(:inbox) { create(:inbox, account: account, name: 'Vendedor') }

  before { sign_in(super_admin, scope: :super_admin) }

  it 'renders the settings page' do
    get '/super_admin/commercial/settings'

    expect(response).to have_http_status(:success)
    expect(response.body).to include('CommercialSettings')
  end

  it 'lists the inboxes of the chosen account' do
    other_account_inbox = create(:inbox, account: create(:account))
    inbox

    get '/super_admin/commercial/settings/inboxes', params: { account_id: account.id }, as: :json

    ids = response.parsed_body.pluck('id')
    expect(ids).to include(inbox.id)
    expect(ids).not_to include(other_account_inbox.id)
  end

  it 'saves the account, the inbox and the reminder time' do
    patch '/super_admin/commercial/settings', params: { account_id: account.id, inbox_id: inbox.id, reminder_time: '12:30' }, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include('account_id' => account.id, 'inbox_id' => inbox.id, 'reminder_time' => '12:30')
    expect(Sales::LeadWhatsappMessenger.inbox_id).to eq(inbox.id)
  end

  it 'refuses an inbox that is not from the chosen account' do
    patch '/super_admin/commercial/settings',
          params: { account_id: account.id, inbox_id: create(:inbox, account: create(:account)).id, reminder_time: '12:30' }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'refuses a malformed reminder time' do
    patch '/super_admin/commercial/settings', params: { account_id: account.id, inbox_id: inbox.id, reminder_time: '25:99' }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end
end
