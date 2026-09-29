require 'rails_helper'

# Contacts are shared across the account, so group actions also require
# access to the inbox the group lives on.
RSpec.describe 'WhatsApp group actions and inbox access', type: :request do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'baileys', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:group) { create(:contact, account: account, group_type: :group, identifier: '120363000000000000@g.us') }

  before { create(:conversation, account: account, contact: group, inbox: inbox, group_type: :group) }

  it 'refuses an agent who is not in the group inbox' do
    get "/api/v1/accounts/#{account.id}/contacts/#{group.id}/group_members", headers: agent.create_new_auth_token

    expect(response).to have_http_status(:unauthorized)
  end

  it 'refuses a group sync to an agent who is not in the group inbox' do
    post "/api/v1/accounts/#{account.id}/contacts/#{group.id}/sync_group", headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(Contacts::SyncGroupJob).not_to have_been_enqueued
  end

  it 'lets an agent of the group inbox in' do
    create(:inbox_member, user: agent, inbox: inbox)

    get "/api/v1/accounts/#{account.id}/contacts/#{group.id}/group_members", headers: agent.create_new_auth_token

    expect(response).to have_http_status(:success)
  end

  it 'lets an administrator in without inbox membership' do
    admin = create(:user, account: account, role: :administrator)

    get "/api/v1/accounts/#{account.id}/contacts/#{group.id}/group_members", headers: admin.create_new_auth_token

    expect(response).to have_http_status(:success)
  end
end
