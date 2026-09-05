require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::TermsAcceptances', type: :request do
  let(:account) { create(:account) }
  let(:manager) { create(:user, account: account, role: :agent) } # role is on account_user below
  let(:other_manager) { create(:user, account: account, role: :agent) }
  let(:creator) { create(:super_admin) }
  let(:terms_version) { create(:terms_version) }

  let(:request_row) do
    create(:terms_acceptance_request, terms_version: terms_version, created_by: creator)
  end

  # `role:` on the factory only sets the account_user role, which is what
  # OperationsNotification looks at; the campaign row wires the account_user id
  # explicitly.
  let!(:manager_account_user) do
    account.account_users.find_by(user: manager).tap { |au| au.update!(role: :manager) }
  end

  let!(:acceptance) do
    create(:terms_acceptance, terms_acceptance_request: request_row, terms_version: terms_version,
                              account: account, account_user: manager_account_user,
                              status: :pending, kind: :update, deadline_at: 7.days.from_now, required: true)
  end

  let!(:notification) do
    OperationsNotification.create!(
      title: 'Novos termos de uso',
      body: 'Assine para continuar',
      severity: :info,
      scope_type: :all_accounts,
      audience_type: :managers,
      trigger_kind: :on_login,
      published_at: 1.minute.ago,
      created_by: creator,
      subject: request_row
    )
  end

  describe 'POST /api/v1/accounts/:account_id/terms_acceptances/:token/sign' do
    it 'signs the acceptance and stamps signer + audit fields' do
      post "/api/v1/accounts/#{account.id}/terms_acceptances/#{acceptance.request_token}/sign",
           headers: manager.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(acceptance.reload).to have_attributes(
        status: 'signed',
        signer_email: manager.email,
        ip_address: be_present,
        signed_at: be_present
      )
    end

    it 'creates the ack so the modal stops showing this campaign' do
      expect do
        post "/api/v1/accounts/#{account.id}/terms_acceptances/#{acceptance.request_token}/sign",
             headers: manager.create_new_auth_token, as: :json
      end.to change(OperationsNotificationAck, :count).by(1)

      ack = OperationsNotificationAck.last
      expect(ack.operations_notification_id).to eq(notification.id)
      expect(ack.user_id).to eq(manager.id)
    end

    # Every manager sees the notification (audience is role-based), but only
    # the pinned signer can produce the acceptance — otherwise a colleague
    # would put their name on the trail.
    it 'refuses when the signed-in user is not the pinned signer' do
      post "/api/v1/accounts/#{account.id}/terms_acceptances/#{acceptance.request_token}/sign",
           headers: other_manager.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(acceptance.reload.status).to eq('pending')
    end

    it '404s a token that does not exist for this account' do
      post "/api/v1/accounts/#{account.id}/terms_acceptances/does-not-exist/sign",
           headers: manager.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
