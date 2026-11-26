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

  # The edit is written before the channel takes it and written back when the channel refuses, so only
  # an edit the channel accepted reaches the "Message Edited" automations.
  context 'when the inbox edits on the channel' do
    let(:channel) { create(:channel_whatsapp, account: account, provider: 'baileys', validate_provider_config: false, sync_templates: false) }
    let(:inbox) { channel.inbox }
    let(:message) do
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, sender: author,
                       content: 'Oi', source_id: 'WAMID.1')
    end

    before { allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original }

    it 'announces the edit once the channel has accepted it' do
      allow_any_instance_of(Channel::Whatsapp).to receive(:edit_message).and_return(true) # rubocop:disable RSpec/AnyInstance

      edit_as(author)

      expect(response).to have_http_status(:ok)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(Events::Types::MESSAGE_EDITED, anything, anything).once
    end

    it 'announces nothing when the channel refuses the edit' do
      allow_any_instance_of(Channel::Whatsapp).to receive(:edit_message).and_raise(StandardError, 'channel refused') # rubocop:disable RSpec/AnyInstance

      edit_as(author)

      expect(message.reload.content).to eq('Oi')
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(Events::Types::MESSAGE_EDITED, anything, anything)
    end

    it 'announces nothing when the channel refuses a second edit of the message' do
      message.update_columns(content: 'Oi!', content_attributes: { is_edited: true, previous_content: 'Oi' }) # rubocop:disable Rails/SkipsModelValidations
      allow_any_instance_of(Channel::Whatsapp).to receive(:edit_message).and_raise(StandardError, 'channel refused') # rubocop:disable RSpec/AnyInstance

      edit_as(author)

      expect(message.reload.content).to eq('Oi!')
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(Events::Types::MESSAGE_EDITED, anything, anything)
    end
  end
end
