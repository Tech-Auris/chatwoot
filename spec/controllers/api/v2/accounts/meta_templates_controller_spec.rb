require 'rails_helper'

RSpec.describe 'Meta Templates API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:cloud_channel) do
    create(:channel_whatsapp,
           account: account,
           provider: 'whatsapp_cloud',
           validate_provider_config: false,
           sync_templates: false)
  end
  let(:cloud_inbox) { cloud_channel.inbox }
  let(:baileys_channel) do
    create(:channel_whatsapp,
           account: account,
           provider: 'baileys',
           validate_provider_config: false,
           sync_templates: false)
  end
  let(:baileys_inbox) { baileys_channel.inbox }

  let(:sample_templates) do
    [
      {
        'id' => '123',
        'name' => 'confirmacao_agenda',
        'status' => 'APPROVED',
        'category' => 'UTILITY',
        'language' => 'pt_BR',
        'components' => [{ 'type' => 'BODY', 'text' => 'Olá {{1}}' }]
      }
    ]
  end

  before do
    cloud_channel.update!(message_templates: sample_templates, message_templates_last_updated: Time.current)
  end

  describe 'GET /api/v2/accounts/{account_id}/meta_templates' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v2/accounts/#{account.id}/meta_templates", params: { inbox_id: cloud_inbox.id }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns the cached templates for the given cloud inbox' do
        get "/api/v2/accounts/#{account.id}/meta_templates",
            params: { inbox_id: cloud_inbox.id }, headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body['inbox']['id']).to eq(cloud_inbox.id)
        expect(body['templates'].size).to eq(1)
        expect(body['templates'].first['name']).to eq('confirmacao_agenda')
        expect(body['last_synced_at']).to be_present
      end

      it 'is available to agents (sidebar hides it on Baileys-only accounts already)' do
        get "/api/v2/accounts/#{account.id}/meta_templates",
            params: { inbox_id: cloud_inbox.id }, headers: agent.create_new_auth_token

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['templates'].size).to eq(1)
      end

      it 'returns 422 when the inbox is not a Cloud WhatsApp inbox' do
        get "/api/v2/accounts/#{account.id}/meta_templates",
            params: { inbox_id: baileys_inbox.id }, headers: admin.create_new_auth_token

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to be_present
      end

      it 'returns 404 when the inbox belongs to a different account' do
        other_account = create(:account)
        other_channel = create(:channel_whatsapp, account: other_account, provider: 'whatsapp_cloud',
                                                  validate_provider_config: false, sync_templates: false)

        get "/api/v2/accounts/#{account.id}/meta_templates",
            params: { inbox_id: other_channel.inbox.id }, headers: admin.create_new_auth_token

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v2/accounts/{account_id}/meta_templates/sync' do
    let(:refreshed) do
      [
        {
          'id' => '456',
          'name' => 'confirmacao_agenda',
          'status' => 'PENDING',
          'category' => 'UTILITY',
          'language' => 'pt_BR',
          'components' => [{ 'type' => 'BODY', 'text' => 'Nova versão em análise' }]
        }
      ]
    end

    it 'triggers an inline sync and returns the fresh templates' do
      # rubocop:disable RSpec/AnyInstance — controller loads the channel via
      # `Current.account.inboxes.find(...).channel`, so intercepting a specific
      # instance would require re-plumbing the controller with a boundary that
      # doesn't exist yet. The stub is scoped to this example.
      allow_any_instance_of(Channel::Whatsapp).to receive(:sync_templates) do
        cloud_channel.update!(message_templates: refreshed, message_templates_last_updated: Time.current)
      end
      # rubocop:enable RSpec/AnyInstance

      post "/api/v2/accounts/#{account.id}/meta_templates/sync",
           params: { inbox_id: cloud_inbox.id }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['templates'].first['status']).to eq('PENDING')
    end

    it 'returns 422 with a friendly error when Meta refresh raises' do
      allow_any_instance_of(Channel::Whatsapp).to receive(:sync_templates).and_raise(StandardError, 'boom') # rubocop:disable RSpec/AnyInstance

      post "/api/v2/accounts/#{account.id}/meta_templates/sync",
           params: { inbox_id: cloud_inbox.id }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to be_present
    end
  end

  describe 'POST /api/v2/accounts/{account_id}/meta_templates' do
    let(:valid_payload) do
      {
        inbox_id: cloud_inbox.id,
        template: {
          name: 'confirmacao_agenda',
          language: 'pt_BR',
          category: 'UTILITY',
          components: [
            {
              type: 'BODY',
              text: 'Olá {{1}}, seu agendamento é dia {{2}} às {{3}}.',
              example: { body_text: [%w[Fabio 12/08/2026 10:00]] }
            }
          ]
        }
      }
    end

    it 'creates a template on Meta and refreshes the local cache' do
      # rubocop:disable RSpec/AnyInstance — see comments above the sync
      # examples: intercepting a specific channel instance would require
      # re-plumbing the controller with a boundary that does not exist
      # yet in this small slice.
      provider = instance_double(Whatsapp::Providers::WhatsappCloudService)
      allow_any_instance_of(Channel::Whatsapp).to receive(:provider_service).and_return(provider)
      allow(provider).to receive(:create_template).and_return(
        success: true,
        template: { 'id' => '999', 'status' => 'PENDING', 'category' => 'UTILITY' }
      )
      allow_any_instance_of(Channel::Whatsapp).to receive(:sync_templates) do
        cloud_channel.update!(
          message_templates: sample_templates + [{ 'id' => '999', 'name' => 'confirmacao_agenda',
                                                   'status' => 'PENDING', 'category' => 'UTILITY',
                                                   'language' => 'pt_BR', 'components' => valid_payload[:template][:components] }],
          message_templates_last_updated: Time.current
        )
      end
      # rubocop:enable RSpec/AnyInstance

      post "/api/v2/accounts/#{account.id}/meta_templates",
           params: valid_payload, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body['template']['id']).to eq('999')
      expect(body['templates'].last['name']).to eq('confirmacao_agenda')
    end

    it 'surfaces Meta validation errors as 422 with the original message' do
      provider = instance_double(Whatsapp::Providers::WhatsappCloudService)
      allow_any_instance_of(Channel::Whatsapp).to receive(:provider_service).and_return(provider) # rubocop:disable RSpec/AnyInstance
      allow(provider).to receive(:create_template).and_return(
        success: false,
        error_code: 100,
        error_message: 'Invalid template name',
        error_details: 'Template names must be lowercase.'
      )

      post "/api/v2/accounts/#{account.id}/meta_templates",
           params: valid_payload, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      body = response.parsed_body
      expect(body['error']).to eq('Invalid template name')
      expect(body['details']).to eq('Template names must be lowercase.')
      expect(body['code']).to eq(100)
    end

    it 'forbids agents from creating templates' do
      post "/api/v2/accounts/#{account.id}/meta_templates",
           params: valid_payload, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end

    it 'merges the created template into the cache when the follow-up sync misses it (Meta eventual consistency)' do
      # Real production case: operator submits a new template, the POST to
      # /message_templates succeeds and returns the new id, but the sync
      # GET immediately afterward doesn't yet see it in Meta's list. The
      # cache used to be updated only from the sync, so the operator
      # returned to the index and had to hard-refresh to see their own
      # template. The controller now falls back on the create response
      # to guarantee the row is there.
      # rubocop:disable RSpec/AnyInstance
      provider = instance_double(Whatsapp::Providers::WhatsappCloudService)
      allow_any_instance_of(Channel::Whatsapp).to receive(:provider_service).and_return(provider)
      allow(provider).to receive(:create_template).and_return(
        success: true,
        template: { 'id' => 'new-999', 'status' => 'PENDING', 'category' => 'UTILITY' }
      )
      # Sync returns the PRE-create list (Meta not yet consistent).
      allow_any_instance_of(Channel::Whatsapp).to receive(:sync_templates) do
        cloud_channel.update!(message_templates: sample_templates, message_templates_last_updated: Time.current)
      end
      # rubocop:enable RSpec/AnyInstance

      post "/api/v2/accounts/#{account.id}/meta_templates",
           params: valid_payload, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      row = body['templates'].find { |t| t['id'] == 'new-999' }
      expect(row).to be_present
      expect(row).to include('name' => 'confirmacao_agenda', 'language' => 'pt_BR', 'status' => 'PENDING', 'category' => 'UTILITY')
      expect(row['components']).to be_present
    end

    it 'does not duplicate the created template when the sync already includes it' do
      # rubocop:disable RSpec/AnyInstance
      provider = instance_double(Whatsapp::Providers::WhatsappCloudService)
      allow_any_instance_of(Channel::Whatsapp).to receive(:provider_service).and_return(provider)
      allow(provider).to receive(:create_template).and_return(
        success: true,
        template: { 'id' => 'new-999', 'status' => 'PENDING', 'category' => 'UTILITY' }
      )
      allow_any_instance_of(Channel::Whatsapp).to receive(:sync_templates) do
        cloud_channel.update!(
          message_templates: sample_templates + [{ 'id' => 'new-999', 'name' => 'confirmacao_agenda',
                                                   'status' => 'PENDING', 'category' => 'UTILITY',
                                                   'language' => 'pt_BR', 'components' => valid_payload[:template][:components] }],
          message_templates_last_updated: Time.current
        )
      end
      # rubocop:enable RSpec/AnyInstance

      post "/api/v2/accounts/#{account.id}/meta_templates",
           params: valid_payload, headers: admin.create_new_auth_token

      matching = response.parsed_body['templates'].select { |t| t['id'] == 'new-999' }
      expect(matching.size).to eq(1)
    end
  end

  describe 'DELETE /api/v2/accounts/{account_id}/meta_templates/:id' do
    it 'deletes the template on Meta by name resolved from the cached id, then refreshes the local cache' do
      # rubocop:disable RSpec/AnyInstance — same caveat as the create/sync
      # examples above: the controller reaches through
      # Current.account.inboxes.find(...).channel.provider_service and we do
      # not have a boundary to intercept a specific instance yet.
      provider = instance_double(Whatsapp::Providers::WhatsappCloudService)
      allow_any_instance_of(Channel::Whatsapp).to receive(:provider_service).and_return(provider)
      allow(provider).to receive(:delete_template).with('confirmacao_agenda').and_return(success: true)
      allow_any_instance_of(Channel::Whatsapp).to receive(:sync_templates) do
        cloud_channel.update!(message_templates: [], message_templates_last_updated: Time.current)
      end
      # rubocop:enable RSpec/AnyInstance

      delete "/api/v2/accounts/#{account.id}/meta_templates/123",
             params: { inbox_id: cloud_inbox.id }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['templates']).to eq([])
    end

    it 'returns 404 when the id is not in the cached template list' do
      delete "/api/v2/accounts/#{account.id}/meta_templates/999",
             params: { inbox_id: cloud_inbox.id }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to be_present
    end

    it 'surfaces Meta failure messages as 422' do
      provider = instance_double(Whatsapp::Providers::WhatsappCloudService)
      allow_any_instance_of(Channel::Whatsapp).to receive(:provider_service).and_return(provider) # rubocop:disable RSpec/AnyInstance
      allow(provider).to receive(:delete_template).and_return(
        success: false,
        error_code: 100,
        error_message: 'Template is in use by an active campaign',
        error_details: 'Remove the template from the campaign before deleting.'
      )

      delete "/api/v2/accounts/#{account.id}/meta_templates/123",
             params: { inbox_id: cloud_inbox.id }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      body = response.parsed_body
      expect(body['error']).to eq('Template is in use by an active campaign')
      expect(body['details']).to eq('Remove the template from the campaign before deleting.')
    end

    it 'forbids agents from deleting templates' do
      delete "/api/v2/accounts/#{account.id}/meta_templates/123",
             params: { inbox_id: cloud_inbox.id }, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /api/v2/accounts/{account_id}/meta_templates/:id' do
    let(:update_payload) do
      {
        inbox_id: cloud_inbox.id,
        template: {
          category: 'UTILITY',
          components: [{ type: 'BODY', text: 'Novo texto' }]
        }
      }
    end

    it 'updates the template on Meta and refreshes the cache' do
      # rubocop:disable RSpec/AnyInstance — see prior comments; controller
      # reaches through Current.account.inboxes.find(...).channel and we
      # do not have a boundary to intercept a specific instance yet.
      provider = instance_double(Whatsapp::Providers::WhatsappCloudService)
      allow_any_instance_of(Channel::Whatsapp).to receive(:provider_service).and_return(provider)
      allow(provider).to receive(:update_template).with('123', anything).and_return(
        success: true, template: { 'success' => true }
      )
      allow_any_instance_of(Channel::Whatsapp).to receive(:sync_templates) do
        cloud_channel.update!(
          message_templates: [{ 'id' => '123', 'name' => 'confirmacao_agenda',
                                'status' => 'PENDING', 'category' => 'UTILITY', 'language' => 'pt_BR',
                                'components' => [{ 'type' => 'BODY', 'text' => 'Novo texto' }] }],
          message_templates_last_updated: Time.current
        )
      end
      # rubocop:enable RSpec/AnyInstance

      patch "/api/v2/accounts/#{account.id}/meta_templates/123",
            params: update_payload, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['templates'].first['components'].first['text']).to eq('Novo texto')
    end

    it 'returns 404 when the id is not in the cached template list' do
      patch "/api/v2/accounts/#{account.id}/meta_templates/999",
            params: update_payload, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end

    it 'surfaces Meta refusal (e.g. editing an immutable field) as 422' do
      provider = instance_double(Whatsapp::Providers::WhatsappCloudService)
      allow_any_instance_of(Channel::Whatsapp).to receive(:provider_service).and_return(provider) # rubocop:disable RSpec/AnyInstance
      allow(provider).to receive(:update_template).and_return(
        success: false,
        error_code: 100,
        error_message: 'Cannot edit template in current status',
        error_details: 'Template must be APPROVED or REJECTED to be edited.'
      )

      patch "/api/v2/accounts/#{account.id}/meta_templates/123",
            params: update_payload, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      body = response.parsed_body
      expect(body['error']).to eq('Cannot edit template in current status')
      expect(body['details']).to be_present
    end

    it 'forbids agents from updating templates' do
      patch "/api/v2/accounts/#{account.id}/meta_templates/123",
            params: update_payload, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v2/accounts/{account_id}/meta_templates/:id/analytics' do
    let(:conversation) { create(:conversation, inbox: cloud_inbox, account: account) }

    before do
      # Seed a small funnel so the service returns real counts instead of
      # zero. The controller-level assertions only care about wiring
      # (route → policy → service.call → JSON shape); numeric correctness
      # is exercised in the service spec.
      create(:message, inbox: cloud_inbox, account: account, conversation: conversation,
                       message_type: :outgoing, status: :read, source_id: 'wamid.1',
                       additional_attributes: { 'template_params' => { 'name' => 'confirmacao_agenda', 'language' => 'pt_BR' } })
      create(:message, inbox: cloud_inbox, account: account, conversation: conversation,
                       message_type: :outgoing, status: :failed, source_id: nil,
                       additional_attributes: { 'template_params' => { 'name' => 'confirmacao_agenda', 'language' => 'pt_BR' } })
    end

    it 'returns the funnel payload for the template' do
      get "/api/v2/accounts/#{account.id}/meta_templates/123/analytics",
          params: { inbox_id: cloud_inbox.id, period: '30d' }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['period']).to eq('30d')
      expect(body['template_name']).to eq('confirmacao_agenda')
      expect(body['funnel']).to include('sent' => 2, 'accepted_by_meta' => 1, 'failed_sync' => 1, 'read' => 1)
    end

    it 'is available to agents (read-only, same audience as index)' do
      get "/api/v2/accounts/#{account.id}/meta_templates/123/analytics",
          params: { inbox_id: cloud_inbox.id }, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:success)
    end

    it 'returns 404 when the template id is not in the cached list' do
      get "/api/v2/accounts/#{account.id}/meta_templates/9999/analytics",
          params: { inbox_id: cloud_inbox.id }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end

    it 'falls back to 30d silently when an unknown period is passed' do
      get "/api/v2/accounts/#{account.id}/meta_templates/123/analytics",
          params: { inbox_id: cloud_inbox.id, period: 'lifetime' }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['period']).to eq('30d')
    end
  end

  describe 'POST /api/v2/accounts/{account_id}/meta_templates/upload_header_media' do
    # 2×2 red PNG — minimum valid PNG, small enough to embed. Anything
    # bigger would need a fixture file, and this test only cares that the
    # request reaches provider_service.upload_template_header_media with
    # the right shape — the actual Meta call is stubbed.
    let(:png_bytes) do
      Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAF0lEQVR42mP8/5+hnoEIwDiqkL5KAQAxpQP1Yjg9OwAAAABJRU5ErkJggg==')
    end
    let(:file) { Rack::Test::UploadedFile.new(StringIO.new(png_bytes), 'image/png', original_filename: 'logo.png') }

    it 'proxies the file to the provider and returns the Meta handle' do
      # rubocop:disable RSpec/AnyInstance — controller resolves the channel
      # through `Current.account.inboxes.find(...).channel.provider_service`;
      # we don't have a boundary to intercept a specific channel instance.
      provider = instance_double(Whatsapp::Providers::WhatsappCloudService)
      allow_any_instance_of(Channel::Whatsapp).to receive(:provider_service).and_return(provider)
      # rubocop:enable RSpec/AnyInstance
      allow(provider).to receive(:upload_template_header_media)
        .with(hash_including(file_name: 'logo.png', file_type: 'image/png'))
        .and_return(success: true, handle: '4::abcdef')

      post "/api/v2/accounts/#{account.id}/meta_templates/upload_header_media",
           params: { inbox_id: cloud_inbox.id, file: file }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['handle']).to eq('4::abcdef')
    end

    it 'returns 422 when the file mime type is not JPG/PNG' do
      pdf = Rack::Test::UploadedFile.new(StringIO.new('%PDF-1.4'), 'application/pdf', original_filename: 'x.pdf')

      post "/api/v2/accounts/#{account.id}/meta_templates/upload_header_media",
           params: { inbox_id: cloud_inbox.id, file: pdf }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to match(/Unsupported file type/)
    end

    it 'returns 422 when the file is missing' do
      post "/api/v2/accounts/#{account.id}/meta_templates/upload_header_media",
           params: { inbox_id: cloud_inbox.id }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('A file is required')
    end

    it 'forbids agents from uploading media' do
      post "/api/v2/accounts/#{account.id}/meta_templates/upload_header_media",
           params: { inbox_id: cloud_inbox.id, file: file }, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end

    it 'surfaces Meta failures as 422 with the original error text' do
      # rubocop:disable RSpec/AnyInstance
      provider = instance_double(Whatsapp::Providers::WhatsappCloudService)
      allow_any_instance_of(Channel::Whatsapp).to receive(:provider_service).and_return(provider)
      # rubocop:enable RSpec/AnyInstance
      allow(provider).to receive(:upload_template_header_media).and_return(
        success: false, error_code: 100, error_message: 'file_type not supported', error_details: 'Use JPG or PNG.'
      )

      post "/api/v2/accounts/#{account.id}/meta_templates/upload_header_media",
           params: { inbox_id: cloud_inbox.id, file: file }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      body = response.parsed_body
      expect(body['error']).to eq('file_type not supported')
      expect(body['details']).to eq('Use JPG or PNG.')
      expect(body['code']).to eq(100)
    end
  end
end
