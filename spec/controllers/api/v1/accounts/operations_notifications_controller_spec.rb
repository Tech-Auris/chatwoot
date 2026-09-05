require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::OperationsNotifications', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_user) { create(:user, account: account, role: :agent) }
  let(:creator) { create(:user, account: account) }

  let!(:notification) do
    OperationsNotification.create!(
      title: 'Manutenção programada',
      body: 'Vamos derrubar o sistema 5 minutos',
      severity: :info,
      scope_type: :all_accounts,
      audience_type: :all_users,
      trigger_kind: :on_login,
      published_at: 1.minute.ago,
      created_by: creator
    )
  end

  describe 'GET /pending' do
    it 'returns the notification when not acked yet' do
      get pending_api_v1_account_operations_notifications_path(account.id),
          headers: agent.create_new_auth_token
      expect(response).to have_http_status(:ok)
      payload = response.parsed_body.dig('data', 'payload')
      expect(payload.length).to eq(1)
      expect(payload.first['title']).to eq('Manutenção programada')
      expect(payload.first['acknowledged_at']).to be_nil
    end

    it 'hides the notification after ack' do
      OperationsNotificationAck.create!(
        operations_notification: notification, user: agent, account: account, acknowledged_at: Time.current
      )
      get pending_api_v1_account_operations_notifications_path(account.id),
          headers: agent.create_new_auth_token
      payload = response.parsed_body.dig('data', 'payload')
      expect(payload).to be_empty
    end
  end

  describe 'GET /' do
    it 'returns the notification with acknowledged_at populated when acked' do
      OperationsNotificationAck.create!(
        operations_notification: notification, user: agent, account: account, acknowledged_at: Time.current
      )
      get api_v1_account_operations_notifications_path(account.id),
          headers: agent.create_new_auth_token
      payload = response.parsed_body.dig('data', 'payload')
      expect(payload.length).to eq(1)
      expect(payload.first['acknowledged_at']).not_to be_nil
    end

    it 'does not leak acks from other users' do
      OperationsNotificationAck.create!(
        operations_notification: notification, user: other_user, account: account, acknowledged_at: Time.current
      )
      get api_v1_account_operations_notifications_path(account.id),
          headers: agent.create_new_auth_token
      payload = response.parsed_body.dig('data', 'payload')
      expect(payload.first['acknowledged_at']).to be_nil
    end
  end

  # A campaign notification is audience-scoped to `managers`; on a per-account
  # basis only the pinned signers get the pending row. `/pending` must filter
  # the notification out for a manager who is not on the campaign roster, so
  # the modal does not open a signature they cannot produce.
  describe 'GET /pending with a re-signature campaign' do
    let(:manager) { create(:user, account: account) }
    let(:bystander_manager) { create(:user, account: account) }
    let(:super_admin) { create(:super_admin) }
    let(:terms_version) { create(:terms_version) }
    let(:request_row) do
      create(:terms_acceptance_request, terms_version: terms_version, created_by: super_admin)
    end
    let!(:manager_account_user) do
      account.account_users.find_by(user: manager).tap { |au| au.update!(role: :manager) }
    end
    let!(:acceptance) do
      create(:terms_acceptance, terms_acceptance_request: request_row, terms_version: terms_version,
                                account: account, account_user: manager_account_user,
                                status: :pending, kind: :update, deadline_at: 7.days.from_now, required: true)
    end

    # Promotes the bystander to manager so they DO match the OpsNotif
    # audience — the point of the spec is to prove the terms-specific
    # filter kicks in on top of the role audience — then publishes the
    # campaign notification.
    before do
      account.account_users.find_by(user: bystander_manager).update!(role: :manager)

      OperationsNotification.create!(
        title: 'Novos termos', body: 'Assine para continuar',
        severity: :info, scope_type: :all_accounts, audience_type: :managers, trigger_kind: :on_login,
        published_at: 1.minute.ago, created_by: super_admin, subject: request_row
      )
    end

    it 'shows the campaign to the pinned signer with terms payload attached' do
      get pending_api_v1_account_operations_notifications_path(account.id),
          headers: manager.create_new_auth_token
      payload = response.parsed_body.dig('data', 'payload')
      terms_item = payload.find { |n| n['subject_type'] == 'TermsAcceptanceRequest' }

      expect(terms_item).to be_present
      expect(terms_item.dig('terms_acceptance', 'token')).to eq(acceptance.request_token)
      expect(terms_item.dig('terms_version', 'content')).to eq(terms_version.content)
    end

    it 'hides the campaign from a manager not on the roster' do
      get pending_api_v1_account_operations_notifications_path(account.id),
          headers: bystander_manager.create_new_auth_token
      payload = response.parsed_body.dig('data', 'payload')

      expect(payload.map { |n| n['subject_type'] }).not_to include('TermsAcceptanceRequest')
    end

    it 'hides the campaign after the pinned signer signs it' do
      acceptance.sign!(signer: { name: 'a', email: 'a@b.c', document: nil }, ip_address: '1.1.1.1', user_agent: 'rspec')

      get pending_api_v1_account_operations_notifications_path(account.id),
          headers: manager.create_new_auth_token
      payload = response.parsed_body.dig('data', 'payload')

      expect(payload.map { |n| n['subject_type'] }).not_to include('TermsAcceptanceRequest')
    end
  end

  describe 'POST /:id/acknowledge' do
    it 'creates an ack with ip and user_agent captured' do
      post acknowledge_api_v1_account_operations_notification_path(account.id, notification.id),
           headers: agent.create_new_auth_token.merge('HTTP_USER_AGENT' => 'rspec-agent')
      expect(response).to have_http_status(:ok)
      ack = OperationsNotificationAck.find_by!(operations_notification: notification, user: agent)
      expect(ack.account_id).to eq(account.id)
      expect(ack.user_agent).to eq('rspec-agent')
      expect(ack.ip).to be_present
    end

    it 'is idempotent on repeated calls' do
      2.times do
        post acknowledge_api_v1_account_operations_notification_path(account.id, notification.id),
             headers: agent.create_new_auth_token
      end
      expect(OperationsNotificationAck.where(operations_notification: notification, user: agent).count).to eq(1)
    end
  end
end
