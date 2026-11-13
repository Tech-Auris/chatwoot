# Daily: deletes the activity log rows older than the retention set in
# Super Admin (ACTIVITY_LOG_RETENTION_MONTHS, 12 months by default).
class ActivityLogs::PurgeJob < ApplicationJob
  queue_as :scheduled_jobs

  DEFAULT_RETENTION_MONTHS = 12

  def perform
    months = GlobalConfigService.load('ACTIVITY_LOG_RETENTION_MONTHS', DEFAULT_RETENTION_MONTHS).to_i
    # A blank or zero value would wipe the whole history.
    months = DEFAULT_RETENTION_MONTHS unless months.positive?

    ActivityLog.where(created_at: ...months.months.ago).in_batches(of: 5_000).delete_all
  end
end
