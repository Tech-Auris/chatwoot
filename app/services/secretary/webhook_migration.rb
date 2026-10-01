# One-shot move of the secretary account webhooks into the Super Admin
# secretary config: per account, the version, the inboxes it answers on and
# the webhook secret are copied, then the webhook is deleted — in a single
# transaction, so a message is never delivered twice nor dropped.
#
# Suspended accounts end up with no secretary. Dry run unless `apply: true`.
class Secretary::WebhookMigration
  VERSIONS = [
    { name: 'v2.2', webhook_url: 'https://n8n.auris.ia.br/webhook/77fb08d0-c63f-4405-9fa3-2e9aa728c905',
      workflow_id: 'aSnlIjOhLud5kafU', released_at: '2025-12-19T22:00:00Z' },
    { name: 'v3.2', webhook_url: 'https://n8n.auris.ia.br/webhook/87dd35b4-4f1f-4d7e-ba01-ca6bab6b5816v3_2new',
      workflow_id: 'jyNvSmsvnvMwo6lK', released_at: '2026-05-14T00:30:55Z' },
    { name: 'v3.3', webhook_url: 'https://n8n.auris.ia.br/webhook/7bedb5a2-38c1-4434-a0d5-540084329bc3_v3_3',
      workflow_id: 'JXves6v2uA9jAkDC', released_at: '2026-09-24T00:30:55Z' }
  ].freeze

  Row = Struct.new(:webhook, :version_name, :suspended, :inbox_ids, keyword_init: true)

  def initialize(apply: false)
    @apply = apply
  end

  def perform
    rows = plan
    apply!(rows) if @apply
    rows
  end

  private

  def plan
    by_url = VERSIONS.index_by { |version| version[:webhook_url] }
    Webhook.includes(:account).where(url: by_url.keys).order(:account_id).map do |webhook|
      suspended = webhook.account.suspended?
      Row.new(webhook: webhook, version_name: by_url[webhook.url][:name], suspended: suspended,
              inbox_ids: suspended ? [] : inbox_ids_for(webhook))
    end
  end

  def inbox_ids_for(webhook)
    return [webhook.inbox_id] if webhook.inbox_id.present?

    webhook.account.inboxes.where.not(channel_type: 'Channel::Simulator').pluck(:id)
  end

  def apply!(rows)
    versions = VERSIONS.to_h { |attrs| [attrs[:name], find_or_create_version(attrs)] }
    rows.each do |row|
      ActiveRecord::Base.transaction { migrate(row, versions[row.version_name]) }
    end
  end

  def find_or_create_version(attrs)
    SecretaryVersion.find_or_create_by!(name: attrs[:name]) do |version|
      version.assign_attributes(attrs.except(:name).merge(nickname: "versão #{attrs[:name]}", status: :active))
    end
  end

  def migrate(row, version)
    account = row.webhook.account
    secretary = account.account_secretary || account.build_account_secretary
    secretary.secret = row.webhook.secret if row.webhook.secret.present?
    secretary.secretary_version = row.suspended ? nil : version
    secretary.save!
    account.inboxes.where(id: row.inbox_ids).update_all(secretary_enabled: true) # rubocop:disable Rails/SkipsModelValidations
    row.webhook.destroy!
  end
end
