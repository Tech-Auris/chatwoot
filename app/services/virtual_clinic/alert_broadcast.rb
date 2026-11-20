# Tells the open dashboards of administrators and managers how many alerts
# each AI teammate has open (the "❗" on the map and the menu badge).
class VirtualClinic::AlertBroadcast
  def initialize(account, users = nil)
    @account = account
    @users = users || account.account_users.where(role: %i[administrator manager]).includes(:user).map(&:user)
  end

  def self.counts(account)
    VirtualClinicAlert.personas.keys.index_with { 0 }.merge(account.virtual_clinic_alerts.open.group(:persona).count)
  end

  def perform
    ActionCableBroadcastJob.perform_later(@users.map(&:pubsub_token), 'virtual_clinic.alerts.updated',
                                          { counts: self.class.counts(@account), account_id: @account.id })
  end
end
