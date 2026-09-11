require 'rails_helper'

RSpec.describe 'Label API', type: :request do
  let!(:account) { create(:account) }
  let!(:label) { create(:label, account: account) }
  let!(:conversation) { create(:conversation, account: account) }

  describe 'GET /api/v1/accounts/{account.id}/labels' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/labels"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :administrator) }

      it 'returns all the labels in account' do
        get "/api/v1/accounts/#{account.id}/labels",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.body).to include(label.title)
      end

      # Once the account moves to the attribute-based AI status, the `agente-off`
      # label no longer wires anything up. Historical tags on old conversations
      # stay in the DB, but the label picker and the sidebar list have to drop
      # it — otherwise the operator adds it thinking it toggles the AI, and
      # nothing happens.
      context 'when the account is on the attribute-based AI status' do
        let!(:legacy_label) { create(:label, account: account, title: 'agente-off') }

        before { account.update!(ai_status_uses_attribute: true) }

        it 'does not return the legacy agente-off label' do
          get "/api/v1/accounts/#{account.id}/labels",
              headers: agent.create_new_auth_token,
              as: :json

          expect(response).to have_http_status(:success)
          titles = response.parsed_body['payload'].pluck('title')
          expect(titles).to include(label.title)
          expect(titles).not_to include(legacy_label.title)
        end
      end

      # Accounts still on the legacy label mode need to keep seeing it — the
      # label is the on/off switch itself. Hiding it there would break the
      # only way to turn the AI off for that account.
      context 'when the account is still on the label-based AI status' do
        let!(:legacy_label) { create(:label, account: account, title: 'agente-off') }

        it 'still returns the agente-off label' do
          get "/api/v1/accounts/#{account.id}/labels",
              headers: agent.create_new_auth_token,
              as: :json

          titles = response.parsed_body['payload'].pluck('title')
          expect(titles).to include(legacy_label.title)
        end
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/labels/:id' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/labels/#{label.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:admin) { create(:user, account: account, role: :administrator) }

      it 'shows the contact' do
        get "/api/v1/accounts/#{account.id}/labels/#{label.id}",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.body).to include(label.title)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/labels' do
    let(:valid_params) { { label: { title: 'test' } } }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        expect { post "/api/v1/accounts/#{account.id}/labels", params: valid_params }.not_to change(Label, :count)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:admin) { create(:user, account: account, role: :administrator) }

      it 'creates the contact' do
        expect do
          post "/api/v1/accounts/#{account.id}/labels", headers: admin.create_new_auth_token,
                                                        params: valid_params
        end.to change(Label, :count).by(1)

        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/labels/:id' do
    let(:valid_params) { { title: 'Test_2' }  }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        put "/api/v1/accounts/#{account.id}/labels/#{label.id}",
            params: valid_params

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:admin) { create(:user, account: account, role: :administrator) }

      it 'updates the label' do
        patch "/api/v1/accounts/#{account.id}/labels/#{label.id}",
              headers: admin.create_new_auth_token,
              params: valid_params,
              as: :json

        expect(response).to have_http_status(:success)
        expect(label.reload.title).to eq('test_2')
      end
    end
  end

  describe 'protected label modifications' do
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:agente_off_label) { create(:label, account: account, title: 'agente-off') }
    let(:kb_label) { create(:label, account: account, title: 'kb-suporte') }

    it 'blocks administrators from updating the agente-off label' do
      patch "/api/v1/accounts/#{account.id}/labels/#{agente_off_label.id}",
            headers: admin.create_new_auth_token,
            params: { title: 'something-else' },
            as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(agente_off_label.reload.title).to eq('agente-off')
    end

    it 'blocks administrators from deleting the agente-off label' do
      delete "/api/v1/accounts/#{account.id}/labels/#{agente_off_label.id}",
             headers: admin.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(Label.find_by(id: agente_off_label.id)).to be_present
    end

    it 'blocks administrators from updating any kb-* label' do
      patch "/api/v1/accounts/#{account.id}/labels/#{kb_label.id}",
            headers: admin.create_new_auth_token,
            params: { title: 'something-else' },
            as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(kb_label.reload.title).to eq('kb-suporte')
    end

    it 'allows administrators to modify regular labels' do
      regular = create(:label, account: account, title: 'cliente')

      patch "/api/v1/accounts/#{account.id}/labels/#{regular.id}",
            headers: admin.create_new_auth_token,
            params: { title: 'cliente-vip' },
            as: :json

      expect(response).to have_http_status(:success)
      expect(regular.reload.title).to eq('cliente-vip')
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/labels/:id' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/labels/#{label.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:admin) { create(:user, account: account, role: :administrator) }

      it 'deletes the label and enqueues label cleanup' do
        label_deleted_at = Time.zone.parse('2026-05-07 10:00:00 UTC')
        conversation.label_list.add(label.title)
        conversation.save!

        clear_enqueued_jobs

        travel_to(label_deleted_at) do
          expect do
            delete "/api/v1/accounts/#{account.id}/labels/#{label.id}", headers: admin.create_new_auth_token, as: :json
          end.to have_enqueued_job(Labels::RemoveAssociationsJob).with(
            label_title: label.title,
            account_id: account.id,
            label_deleted_at: label_deleted_at
          )
        end

        expect(response).to have_http_status(:ok)
        expect(Label.exists?(label.id)).to be(false)
      end
    end
  end
end
