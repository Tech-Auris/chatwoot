require 'rails_helper'

RSpec.describe ActivityLog do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  after { Current.reset }

  describe 'Auditable' do
    it 'logs a create with the new values, as the system from a job when nothing set the context' do
      label = create(:label, account: account, title: 'vip')

      log = described_class.find_by!(auditable_type: 'Label', auditable_id: label.id)
      expect(log).to have_attributes(account_id: account.id, action: 'create', auditable_label: 'vip',
                                     actor_type: 'System', actor_id: nil, source: 'job')
      expect(log.audited_changes['title']).to eq([nil, 'vip'])
      expect(log.audited_changes).not_to have_key('created_at')
    end

    it 'logs an update with before → after, as the current user and origin' do
      contact = create(:contact, account: account, name: 'Maria')
      Current.user = admin
      Current.audit_source = 'dashboard'
      Current.audit_ip = '10.0.0.1'

      contact.update!(name: 'Maria Silva')

      log = described_class.where(auditable_type: 'Contact', auditable_id: contact.id, action: 'update').sole
      expect(log).to have_attributes(actor_type: 'User', actor_id: admin.id, actor_label: admin.name,
                                     source: 'dashboard', ip_address: '10.0.0.1', auditable_label: 'Maria Silva')
      expect(log.audited_changes).to eq('name' => ['Maria', 'Maria Silva'])
    end

    it 'skips an update that only touches ignored fields' do
      contact = create(:contact, account: account)

      expect { contact.update!(last_activity_at: Time.current) }.not_to change(described_class, :count)
    end

    it 'logs a destroy with the values the record had' do
      label = create(:label, account: account, title: 'vip')

      label.destroy!

      log = described_class.find_by!(auditable_type: 'Label', auditable_id: label.id, action: 'destroy')
      expect(log.audited_changes['title']).to eq(['vip', nil])
    end

    it 'never stores secrets' do
      webhook = create(:webhook, account: account)

      log = described_class.find_by!(auditable_type: 'Webhook', auditable_id: webhook.id)
      expect(log.audited_changes['secret']).to eq([described_class::FILTERED, described_class::FILTERED])
      expect(log.audited_changes.to_json).not_to include(webhook.secret)
    end

    it 'filters secrets nested in json fields' do
      changes = described_class.scrub_changes({ 'settings' => [{}, { 'api_key' => 'sk-1', 'region' => 'us' }] }, [])

      expect(changes['settings']).to eq([{}, { 'api_key' => described_class::FILTERED, 'region' => 'us' }])
    end

    it 'logs only the AI switch and the assignee on conversations' do
      conversation = create(:conversation, account: account)

      expect { conversation.update!(status: :resolved) }.not_to change(described_class, :count)

      conversation.update!(ai_enabled: false, assignee: admin)

      log = described_class.where(auditable_type: 'Conversation', auditable_id: conversation.id).sole
      expect(log.audited_changes).to eq('ai_enabled' => [true, false], 'assignee_id' => [nil, admin.id])
      expect(log.auditable_label).to eq("##{conversation.display_id}")
    end

    it 'resolves the account of models without account_id' do
      inbox_member = create(:inbox_member, inbox: create(:inbox, account: account), user: admin)

      log = described_class.find_by!(auditable_type: 'InboxMember', auditable_id: inbox_member.id)
      expect(log.account_id).to eq(account.id)
    end

    it 'logs the API token owner with origin api' do
      contact = create(:contact, account: account)
      Current.user = create(:agent_bot, account: account)
      Current.audit_source = 'api'

      contact.update!(email: 'novo@example.com')

      log = described_class.where(auditable_type: 'Contact', action: 'update').sole
      expect(log).to have_attributes(actor_type: 'AgentBot', source: 'api')
    end

    it 'logs a contact merge on the contact that stays' do
      base = create(:contact, account: account)
      mergee = create(:contact, account: account, name: 'Duplicado')

      ContactMergeAction.new(account: account, base_contact: base, mergee_contact: mergee).perform

      log = described_class.find_by!(auditable_type: 'Contact', auditable_id: base.id, action: 'merge')
      expect(log.audited_changes['merged_contact']).to eq(["Duplicado (##{mergee.id})", nil])
    end
  end

  describe '.record_session!' do
    it 'writes one row per account of the user' do
      other_account = create(:account)
      create(:account_user, account: other_account, user: admin)

      described_class.record_session!(admin, 'sign_in', ip_address: '1.2.3.4', request_id: 'req-1')

      expect(described_class.where(action: 'sign_in').pluck(:account_id)).to contain_exactly(account.id, other_account.id)
      expect(described_class.where(action: 'sign_in').first).to have_attributes(actor_type: 'User', actor_id: admin.id, source: 'login')
    end
  end
end
