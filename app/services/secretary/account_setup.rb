# Saves the Super Admin "Secretária" section of an account: version,
# Simulador version and the inboxes it answers on (the Simulador is never
# one of them — it has its own version).
class Secretary::AccountSetup
  def initialize(account)
    @account = account
  end

  def update!(secretary_version_id:, simulator_version_id:, inbox_ids:)
    secretary = @account.account_secretary || @account.build_account_secretary
    ActiveRecord::Base.transaction do
      secretary.update!(secretary_version_id: secretary_version_id.presence, simulator_version_id: simulator_version_id.presence)
      ids = Array(inbox_ids).compact_blank.map(&:to_i)
      regular_inboxes.where(id: ids).update_all(secretary_enabled: true) # rubocop:disable Rails/SkipsModelValidations
      regular_inboxes.where.not(id: ids).update_all(secretary_enabled: false) # rubocop:disable Rails/SkipsModelValidations
    end
    secretary
  end

  private

  def regular_inboxes
    @account.inboxes.where.not(channel_type: 'Channel::Simulator')
  end
end
