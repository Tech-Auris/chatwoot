require 'rails_helper'

RSpec.describe ActivityLogs::PurgeJob do
  let(:account) { create(:account) }

  def log_at(time)
    ActivityLog.create!(account_id: account.id, auditable_type: 'Label', action: 'create',
                        actor_type: 'System', source: 'job', created_at: time)
  end

  it 'deletes the rows older than 12 months by default' do
    old_log = log_at(13.months.ago)
    recent_log = log_at(11.months.ago)

    described_class.perform_now

    expect(ActivityLog.exists?(old_log.id)).to be(false)
    expect(ActivityLog.exists?(recent_log.id)).to be(true)
  end

  it 'uses the retention set in Super Admin' do
    InstallationConfig.where(name: 'ACTIVITY_LOG_RETENTION_MONTHS').first_or_create!(value: 3)
    GlobalConfig.clear_cache
    old_log = log_at(4.months.ago)
    recent_log = log_at(2.months.ago)

    described_class.perform_now

    expect(ActivityLog.exists?(old_log.id)).to be(false)
    expect(ActivityLog.exists?(recent_log.id)).to be(true)
  end
end
