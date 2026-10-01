# Rollback of `Secretary::WebhookMigration`: recreates the account webhook
# (same URL and secret, `message_created`) for every account with a
# secretary version and turns the Super Admin config off, so each message is
# still delivered once.
#
# When the secretary answers on a single inbox of a multi-inbox account the
# webhook is restricted to it; any other subset falls back to all inboxes.
class Secretary::WebhookRestore
  def perform
    AccountSecretary.includes(:account, :secretary_version).where.not(secretary_version_id: nil).map do |secretary|
      ActiveRecord::Base.transaction { restore(secretary) }
    end
  end

  private

  def restore(secretary)
    account = secretary.account
    version = secretary.secretary_version
    webhook = account.webhooks.new(url: version.webhook_url, inbox_id: single_inbox_id(account), name: "Secretária #{version.name}",
                                   subscriptions: ['message_created'], secret: secretary.secret)
    # The URL belongs to a secretary version, which the webhook validation refuses.
    webhook.save!(validate: false)
    secretary.update!(secretary_version: nil)
    account.inboxes.update_all(secretary_enabled: false) # rubocop:disable Rails/SkipsModelValidations
    webhook
  end

  def single_inbox_id(account)
    regular = account.inboxes.where.not(channel_type: 'Channel::Simulator')
    enabled = regular.where(secretary_enabled: true).pluck(:id)
    enabled.first if enabled.size == 1 && regular.count > 1
  end
end
