# Tells the open dashboards of administrators and managers how many alerts
# each AI teammate has open (the "❗" on the map and the menu badge).
class VirtualClinic::AlertBroadcast
  def initialize(account, users = nil)
    @account = account
    @users = users || account.account_users.where(role: %i[administrator manager]).includes(:user).map(&:user)
  end

  # Each person counts the team's alerts plus their own (summaries).
  def self.counts(account, user)
    VirtualClinicAlert.personas.keys.index_with { 0 }.merge(account.virtual_clinic_alerts.open.seen_by(user).group(:persona).count)
  end

  def perform
    @users.each do |user|
      ActionCableBroadcastJob.perform_later([user.pubsub_token], 'virtual_clinic.alerts.updated',
                                            { counts: self.class.counts(@account, user), account_id: @account.id })
    end
  end
end
