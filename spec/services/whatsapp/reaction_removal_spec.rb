require 'rails_helper'

# Regression: the reactions controller reuses the reaction row and marks it deleted on removal, and
# the guard that keeps a deleted message off the channel must not swallow it: the emoji would vanish
# from the dashboard and stay on the contact's phone forever.
RSpec.describe 'WhatsApp reaction removal', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :administrator) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+551187654321', identifier: nil) }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '551187654321') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }

  let!(:target) do
    create(:message, message_type: :incoming, content: 'oi', conversation: conversation,
                     account: account, inbox: inbox, source_id: 'wa_target_1')
  end

  before { create(:inbox_member, inbox: inbox, user: agent) }

  def toggle_reaction(emoji)
    post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{target.id}/reactions",
         params: { emoji: emoji }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    perform_enqueued_jobs(only: SendReplyJob)
  end

  shared_examples 'a removable reaction' do
    it 'sends the empty emoji that clears the reaction on the phone' do
      toggle_reaction('👍')
      toggle_reaction('👍')

      expect(a_request(:post, send_url)).to have_been_made.twice
      expect(reaction_sent_with('👍')).to have_been_made
      expect(reaction_sent_with('')).to have_been_made
    end

    it 'leaves the reaction row deleted and does not revoke it on the provider' do
      toggle_reaction('👍')
      toggle_reaction('👍')

      reaction = conversation.reload.messages.detect(&:reaction?)
      expect(reaction).to be_removed_reaction
      expect(Messages::DeleteOnChannelJob).not_to have_been_enqueued
    end

    it 'still keeps a deleted message off the channel' do
      message = create(:message, message_type: :outgoing, content: 'segredo', conversation: conversation,
                                 account: account, inbox: inbox, source_id: nil)
      message.update!(content_attributes: message.content_attributes.merge('deleted' => true))

      SendReplyJob.perform_now(message.id)

      expect(a_request(:post, send_url)).not_to have_been_made
    end
  end

  context 'with a baileys inbox' do
    let(:channel) { create(:channel_whatsapp, provider: 'baileys', account: account, validate_provider_config: false, sync_templates: false) }
    let(:send_url) { "#{channel.provider_config['provider_url']}/connections/#{channel.phone_number}/send-message" }

    before do
      stub_request(:post, send_url).to_return(
        status: 200,
        body: { data: { key: { id: 'wa_reaction_1' }, messageTimestamp: 1_700_000_000 } }.to_json,
        headers: { 'content-type' => 'application/json' }
      )
    end

    def reaction_sent_with(emoji)
      a_request(:post, send_url).with { |request| JSON.parse(request.body).dig('messageContent', 'react', 'text') == emoji }
    end

    it_behaves_like 'a removable reaction'
  end

  context 'with a whatsapp cloud inbox' do
    let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, validate_provider_config: false, sync_templates: false) }
    let(:send_url) { 'https://graph.facebook.com/v23.0/123456789/messages' }

    before do
      stub_request(:post, send_url).to_return(
        status: 200,
        body: { messages: [{ id: 'wamid.reaction_1' }] }.to_json,
        headers: { 'content-type' => 'application/json' }
      )
    end

    def reaction_sent_with(emoji)
      a_request(:post, send_url).with { |request| JSON.parse(request.body).dig('reaction', 'emoji') == emoji }
    end

    it_behaves_like 'a removable reaction'
  end
end
