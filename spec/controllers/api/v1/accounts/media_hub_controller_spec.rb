require 'rails_helper'

RSpec.describe 'Media Hub API', type: :request do
  let(:account) { create(:account) }
  # Attachments per inbox / kind. Each carries a distinct hint on the parent
  # message content so the tests can pick a row out of the response by name.
  let!(:image_in_a) { attach_to(inbox_a, :image, tag: 'img-a') }
  let!(:image_in_b) { attach_to(inbox_b, :image, tag: 'img-b') }
  let!(:video_in_a) { attach_to(inbox_a, :video, tag: 'vid-a') }
  let!(:audio_in_a) { attach_to(inbox_a, :audio, tag: 'aud-a') }
  let!(:doc_in_a)   { attach_to(inbox_a, :file,  tag: 'doc-a') }
  let!(:link_in_a) do
    conversation = create(:conversation, account: account, inbox: inbox_a)
    create(:message, account: account, conversation: conversation, content: 'link-a https://a.example.com', message_type: :outgoing)
  end
  let!(:link_in_b) do
    conversation = create(:conversation, account: account, inbox: inbox_b)
    create(:message, account: account, conversation: conversation, content: 'link-b https://b.example.com', message_type: :outgoing)
  end
  # Auto-assignment off — creating conversations by the dozen in the
  # pagination test would fan out to Redis round-robin work that has
  # nothing to do with what the Media Hub is exercising.
  let(:inbox_a) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:inbox_b) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:manager) { create(:user, account: account, role: :agent) } # role bumped below
  let(:agent) { create(:user, account: account, role: :agent) }

  before do
    AccountUser.find_by(user: manager, account: account).update!(role: :manager)
    create(:inbox_member, user: agent, inbox: inbox_a)
  end

  describe 'GET /api/v1/accounts/:account_id/media_hub' do
    it 'refuses an unauthenticated request' do
      get "/api/v1/accounts/#{account.id}/media_hub"

      expect(response).to have_http_status(:unauthorized)
    end

    context 'when the current user is an administrator' do
      it 'lists images from every inbox by default' do
        get "/api/v1/accounts/#{account.id}/media_hub",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['meta']).to include('type' => 'image')
        ids = response.parsed_body['items'].map { |i| i['id'] }
        expect(ids).to include(image_in_a.id, image_in_b.id)
      end
    end

    context 'when the current user is a manager' do
      it 'lists media from every inbox — manager sees everything' do
        get "/api/v1/accounts/#{account.id}/media_hub?type=image",
            headers: manager.create_new_auth_token,
            as: :json

        ids = response.parsed_body['items'].map { |i| i['id'] }
        expect(ids).to contain_exactly(image_in_a.id, image_in_b.id)
      end

      it 'lists links from every inbox' do
        get "/api/v1/accounts/#{account.id}/media_hub?type=link",
            headers: manager.create_new_auth_token,
            as: :json

        message_ids = response.parsed_body['items'].map { |i| i['message_id'] }
        expect(message_ids).to include(link_in_a.id, link_in_b.id)
      end
    end

    context 'when the current user is an agent' do
      it 'lists only the media that live in an inbox the agent belongs to' do
        get "/api/v1/accounts/#{account.id}/media_hub?type=image",
            headers: agent.create_new_auth_token,
            as: :json

        ids = response.parsed_body['items'].map { |i| i['id'] }
        expect(ids).to eq([image_in_a.id])
      end

      it 'lists only the links that live in an inbox the agent belongs to' do
        get "/api/v1/accounts/#{account.id}/media_hub?type=link",
            headers: agent.create_new_auth_token,
            as: :json

        message_ids = response.parsed_body['items'].map { |i| i['message_id'] }
        expect(message_ids).to include(link_in_a.id)
        expect(message_ids).not_to include(link_in_b.id)
      end
    end

    it 'splits the media kinds — a `video` type returns videos, not audios or images' do
      get "/api/v1/accounts/#{account.id}/media_hub?type=video",
          headers: admin.create_new_auth_token,
          as: :json

      ids = response.parsed_body['items'].map { |i| i['id'] }
      types = response.parsed_body['items'].map { |i| i['file_type'] }.uniq
      expect(ids).to include(video_in_a.id)
      expect(types).to eq(['video'])
    end

    it 'splits the media kinds — an `audio` type returns audios only' do
      get "/api/v1/accounts/#{account.id}/media_hub?type=audio",
          headers: admin.create_new_auth_token,
          as: :json

      ids = response.parsed_body['items'].map { |i| i['id'] }
      types = response.parsed_body['items'].map { |i| i['file_type'] }.uniq
      expect(ids).to include(audio_in_a.id)
      expect(types).to eq(['audio'])
    end

    it 'splits the media kinds — a `document` type returns files only' do
      get "/api/v1/accounts/#{account.id}/media_hub?type=document",
          headers: admin.create_new_auth_token,
          as: :json

      ids = response.parsed_body['items'].map { |i| i['id'] }
      types = response.parsed_body['items'].map { |i| i['file_type'] }.uniq
      expect(ids).to include(doc_in_a.id)
      expect(types).to eq(['file'])
    end

    it 'paginates so a scroll to the bottom can bring the next page' do
      # PER_PAGE = 60; on page 1 we get up to 60 rows and meta gives total_pages.
      70.times { attach_to(inbox_a, :image, tag: 'pagi') }

      get "/api/v1/accounts/#{account.id}/media_hub?type=image&page=2",
          headers: admin.create_new_auth_token,
          as: :json

      expect(response.parsed_body['meta']['current_page']).to eq(2)
      expect(response.parsed_body['meta']['total_pages']).to be >= 2
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/media_hub' do
    it 'refuses to delete an attachment the agent cannot see' do
      # image_in_b lives in inbox_b, which the agent is not a member of.
      expect do
        delete "/api/v1/accounts/#{account.id}/media_hub",
               params: { type: 'image', ids: [image_in_b.id] },
               headers: agent.create_new_auth_token,
               as: :json
      end.not_to change(Attachment, :count)
      expect(response.parsed_body['deleted']).to eq(0)
    end
  end

  def attach_to(inbox, file_type, tag:)
    conversation = create(:conversation, account: account, inbox: inbox)
    message = create(:message, account: account, conversation: conversation, content: tag, message_type: :outgoing)
    message.attachments.create!(account_id: account.id, file_type: file_type)
  end
end
