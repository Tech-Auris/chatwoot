require 'rails_helper'

RSpec.describe 'Campaigns API', type: :request do
  let(:account) { create(:account) }

  describe 'GET /api/v1/accounts/{account.id}/campaigns' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/campaigns"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:administrator) { create(:user, account: account, role: :administrator) }
      let(:inbox) { create(:inbox, account: account) }
      let!(:campaign) { create(:campaign, account: account, inbox: inbox, trigger_rules: { url: 'https://test.com' }) }

      it 'returns unauthorized for agents' do
        get "/api/v1/accounts/#{account.id}/campaigns",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns all campaigns to administrators' do
        get "/api/v1/accounts/#{account.id}/campaigns",
            headers: administrator.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body.first[:id]).to eq(campaign.display_id)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/campaigns/:id' do
    let(:campaign) { create(:campaign, account: account, trigger_rules: { url: 'https://test.com' }) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:administrator) { create(:user, account: account, role: :administrator) }

      it 'returns unauthorized for agents' do
        get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'shows the campaign for administrators' do
        get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}",
            headers: administrator.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body, symbolize_names: true)[:id]).to eq(campaign.display_id)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/campaigns/:id/report' do
    let(:administrator) { create(:user, account: account, role: :administrator) }
    let(:agent) { create(:user, account: account, role: :agent) }
    # A WhatsApp inbox so the campaign is one_off, which is the only kind that
    # carries a schedule, an audience and a cadence.
    let(:inbox) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                validate_provider_config: false, sync_templates: false).inbox
    end
    let(:campaign) { create(:campaign, account: account, inbox: inbox) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }

    def campaign_message(status:, campaign_id: campaign.id)
      create(:message, account: account, inbox: inbox, conversation: conversation,
                       status: status, additional_attributes: { 'campaign_id' => campaign_id })
    end

    it 'returns unauthorized for agents' do
      get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/report",
          headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end

    # The report page renders the campaign with the same card as the list, so
    # it needs the campaign served the same way the list serves it.
    it 'carries the campaign itself, serialized as the list does' do
      campaign.update!(cadence_seconds: 60, conversation_label: 'promo', audience_file_name: 'lista.csv')

      get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/report",
          headers: administrator.create_new_auth_token

      payload = response.parsed_body['campaign']
      expect(payload).to include(
        'id' => campaign.display_id, 'title' => campaign.title,
        'cadence_seconds' => 60, 'conversation_label' => 'promo', 'audience_file_name' => 'lista.csv'
      )
      expect(payload['inbox']['name']).to eq(inbox.name)
    end

    it 'summarizes what happened to the campaign messages' do
      campaign_message(status: :delivered)
      campaign_message(status: :read)
      campaign_message(status: :failed)

      get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/report",
          headers: administrator.create_new_auth_token

      expect(response.parsed_body['summary']).to include(
        'total' => 3, 'accepted' => 2, 'failed' => 1, 'delivered' => 2, 'read' => 1
      )
      expect(response.parsed_body['summary']['success_rate']).to be_within(0.1).of(66.7)
    end

    # A report that counted another campaign's messages would quietly overstate
    # the reach of this one.
    it 'counts only the messages of this campaign' do
      campaign_message(status: :delivered)
      other = create(:campaign, account: account, inbox: inbox)
      campaign_message(status: :delivered, campaign_id: other.id)

      get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/report",
          headers: administrator.create_new_auth_token

      expect(response.parsed_body['summary']['total']).to eq(1)
    end

    # The column reads "Envio", so it must not fall back to creation when the
    # dispatch stamp exists — every message of a campaign is created at once.
    it 'reports the dispatch time, not the creation time' do
      message = campaign_message(status: :delivered)
      stamped = message.additional_attributes.merge('campaign_dispatch_at' => message.created_at.to_i + 120)
      message.update_columns(additional_attributes: stamped) # rubocop:disable Rails/SkipsModelValidations

      get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/report",
          headers: administrator.create_new_auth_token

      row = response.parsed_body['messages'].first
      expect(row['sent_at']).to eq(row['created_at'] + 120)
    end

    it 'falls back to creation for messages sent before the dispatch stamp existed' do
      campaign_message(status: :delivered)

      get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/report",
          headers: administrator.create_new_auth_token

      row = response.parsed_body['messages'].first
      expect(row['sent_at']).to eq(row['created_at'])
    end

    it 'lists each send with the contact and the conversation to open' do
      message = campaign_message(status: :delivered)

      get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/report",
          headers: administrator.create_new_auth_token

      row = response.parsed_body['messages'].first
      expect(row).to include('id' => message.id, 'status' => 'delivered',
                             'conversation_id' => conversation.display_id)
      expect(row['contact_name']).to eq(conversation.contact.name)
    end

    it 'carries the failure reason so the row explains itself' do
      campaign_message(status: :failed).update!(external_error: 'Template paused')

      get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/report",
          headers: administrator.create_new_auth_token

      expect(response.parsed_body['messages'].first['error']).to eq('Template paused')
    end

    it 'reports zeroes for a campaign that never sent anything' do
      get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/report",
          headers: administrator.create_new_auth_token

      expect(response.parsed_body['summary']).to include('total' => 0, 'success_rate' => 0)
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/campaigns/audience_preview' do
    let(:administrator) { create(:user, account: account, role: :administrator) }
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:label) { create(:label, account: account) }

    it 'returns unauthorized for agents' do
      get "/api/v1/accounts/#{account.id}/campaigns/audience_preview", headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end

    it 'lists the contacts behind the chosen labels' do
      tagged = create(:contact, :with_phone_number, account: account, name: 'Maria')
      tagged.update_labels([label.title])
      create(:contact, :with_phone_number, account: account, name: 'Fora do publico')

      get "/api/v1/accounts/#{account.id}/campaigns/audience_preview",
          params: { label_ids: [label.id] }, headers: administrator.create_new_auth_token

      expect(response.parsed_body['contacts'].pluck('name')).to eq(['Maria'])
      expect(response.parsed_body['meta']).to include('total_count' => 1)
    end

    it 'lists an explicit contact list, as an imported file produces' do
      chosen = create(:contact, :with_phone_number, account: account, name: 'Do arquivo')
      create(:contact, :with_phone_number, account: account, name: 'Outro')

      get "/api/v1/accounts/#{account.id}/campaigns/audience_preview",
          params: { contact_ids: [chosen.id] }, headers: administrator.create_new_auth_token

      expect(response.parsed_body['contacts'].pluck('name')).to eq(['Do arquivo'])
    end

    # The campaign skips contacts with no number, so the preview has to say so
    # rather than promising a delivery that never happens.
    it 'flags contacts that will not receive the campaign' do
      no_phone = create(:contact, account: account, name: 'Sem telefone', phone_number: nil)
      no_phone.update_labels([label.title])

      get "/api/v1/accounts/#{account.id}/campaigns/audience_preview",
          params: { label_ids: [label.id] }, headers: administrator.create_new_auth_token

      expect(response.parsed_body['contacts'].first['will_receive']).to be false
      expect(response.parsed_body['meta']['without_phone_count']).to eq(1)
    end

    it 'paginates the list' do
      contacts = create_list(:contact, 3, :with_phone_number, account: account)
      contacts.each { |contact| contact.update_labels([label.title]) }

      get "/api/v1/accounts/#{account.id}/campaigns/audience_preview",
          params: { label_ids: [label.id], page: 1 }, headers: administrator.create_new_auth_token

      expect(response.parsed_body['meta']).to include('total_count' => 3, 'current_page' => 1)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/campaigns/import_audience' do
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:administrator) { create(:user, account: account, role: :administrator) }
    let(:csv) do
      Rack::Test::UploadedFile.new(
        StringIO.new("id,name,email,phone_number\n1,Maria,maria@exemplo.com,+5511987654321\n"),
        'text/csv',
        original_filename: 'audiencia.csv'
      )
    end

    it 'returns unauthorized for an unauthenticated user' do
      post "/api/v1/accounts/#{account.id}/campaigns/import_audience", params: { file: csv }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns unauthorized for agents' do
      post "/api/v1/accounts/#{account.id}/campaigns/import_audience",
           params: { file: csv }, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end

    # The shared `check_authorization` resolves a policy method named after the
    # action, so a custom action without one blows up with a 500 that reaches
    # the screen as a generic "could not read the file".
    it 'turns the file into contacts for an administrator' do
      post "/api/v1/accounts/#{account.id}/campaigns/import_audience",
           params: { file: csv }, headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['created_count']).to eq(1)
      expect(account.contacts.find(body['contact_ids'].first).phone_number).to eq('+5511987654321')
    end

    it 'answers with a readable message when the file is not usable' do
      bad = Rack::Test::UploadedFile.new(StringIO.new("id,nome\n1,Maria\n"), 'text/csv', original_filename: 'ruim.csv')

      post "/api/v1/accounts/#{account.id}/campaigns/import_audience",
           params: { file: bad }, headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('phone_number')
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/campaigns' do
    let(:inbox) { create(:inbox, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/campaigns",
             params: { inbox_id: inbox.id, title: 'test', message: 'test message' },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:administrator) { create(:user, account: account, role: :administrator) }

      it 'returns unauthorized for agents' do
        post "/api/v1/accounts/#{account.id}/campaigns",
             params: { inbox_id: inbox.id, title: 'test', message: 'test message' },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'creates a new campaign' do
        post "/api/v1/accounts/#{account.id}/campaigns",
             params: { inbox_id: inbox.id, title: 'test', message: 'test message' },
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body, symbolize_names: true)[:title]).to eq('test')
      end

      it 'creates a new ongoing campaign' do
        post "/api/v1/accounts/#{account.id}/campaigns",
             params: { inbox_id: inbox.id, title: 'test', message: 'test message', trigger_rules: { url: 'https://test.com' } },
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body, symbolize_names: true)[:title]).to eq('test')
      end

      it 'throws error when invalid url provided for ongoing campaign' do
        post "/api/v1/accounts/#{account.id}/campaigns",
             params: { inbox_id: inbox.id, title: 'test', message: 'test message', trigger_rules: { url: 'javascript' } },
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'creates a new oneoff campaign' do
        twilio_sms = create(:channel_twilio_sms, account: account)
        twilio_inbox = create(:inbox, channel: twilio_sms, account: account)
        label1 = create(:label, account: account)
        label2 = create(:label, account: account)
        scheduled_at = 2.days.from_now

        post "/api/v1/accounts/#{account.id}/campaigns",
             params: {
               inbox_id: twilio_inbox.id, title: 'test', message: 'test message',
               scheduled_at: scheduled_at,
               audience: [{ type: 'Label', id: label1.id }, { type: 'Label', id: label2.id }]
             },
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        response_data = JSON.parse(response.body, symbolize_names: true)
        expect(response_data[:campaign_type]).to eq('one_off')
        expect(response_data[:scheduled_at].present?).to be true
        expect(response_data[:scheduled_at]).to eq(scheduled_at.to_i)
        expect(response_data[:audience].pluck(:id)).to include(label1.id, label2.id)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/campaigns/:id' do
    let(:inbox) { create(:inbox, account: account) }
    let!(:campaign) { create(:campaign, account: account, trigger_rules: { url: 'https://test.com' }) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        patch "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}",
              params: { inbox_id: inbox.id, title: 'test', message: 'test message' },
              as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:administrator) { create(:user, account: account, role: :administrator) }

      it 'returns unauthorized for agents' do
        patch "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}",
              params: { inbox_id: inbox.id, title: 'test', message: 'test message' },
              headers: agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'updates the campaign' do
        patch "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}",
              params: { inbox_id: inbox.id, title: 'test', message: 'test message' },
              headers: administrator.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body, symbolize_names: true)[:title]).to eq('test')
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/campaigns/:id' do
    let(:inbox) { create(:inbox, account: account) }
    let!(:campaign) { create(:campaign, account: account, trigger_rules: { url: 'https://test.com' }) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}",
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:administrator) { create(:user, account: account, role: :administrator) }

      it 'return unauthorized if agent' do
        delete "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'delete campaign if admin' do
        delete "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}",
               headers: administrator.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        expect(Campaign.exists?(campaign.display_id)).to be false
      end
    end
  end
end
