require 'rails_helper'

RSpec.describe 'Edit message content', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, inbox: inbox, account: account) }
  let(:author) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:manager) { create(:user, account: account, role: :manager) }
  let(:message) do
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, sender: author, content: 'Oi')
  end

  before { [author, other_agent].each { |user| create(:inbox_member, inbox: inbox, user: user) } }

  def edit_as(user)
    patch "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}/edit_content",
          params: { content: 'Olá, tudo bem?' }, headers: user.create_new_auth_token, as: :json
  end

  it 'lets the author edit their own message' do
    edit_as(author)

    expect(response).to have_http_status(:ok)
    expect(message.reload.content).to eq('Olá, tudo bem?')
  end

  it "refuses an agent editing someone else's message" do
    edit_as(other_agent)

    expect(response).to have_http_status(:forbidden)
    expect(message.reload.content).to eq('Oi')
  end

  it "lets a manager fix anyone's message" do
    edit_as(manager)

    expect(response).to have_http_status(:ok)
    expect(message.reload.content).to eq('Olá, tudo bem?')
  end
end
