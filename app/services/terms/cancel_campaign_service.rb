# Closes a re-signature campaign before it runs to term.
#
# The reverse of `Terms::CreateCampaignService`: flips the campaign to
# `closed`, cancels every acceptance still `pending` (audit trail preserves
# them — nothing is deleted), removes the OperationsNotifications the
# create service produced, and drops the scheduled `ExpireCampaignJob` so
# the deadline sweep never runs on an already-closed campaign.
#
# Used both by the super_admin destroy action (a campaign created by
# mistake) and by the wizard's `force: true` path (a super_admin who
# accepted the duplicate-date warning wants the old one out of the way).
class Terms::CancelCampaignService
  def initialize(campaign)
    @campaign = campaign
  end

  def perform
    ApplicationRecord.transaction do
      @campaign.terms_acceptances.status_pending.update_all(status: TermsAcceptance.statuses[:cancelled]) # rubocop:disable Rails/SkipsModelValidations
      OperationsNotification.where(subject: @campaign).find_each(&:soft_delete!)
      cleanup_agent_notice
      @campaign.update!(status: :closed)
    end

    drop_scheduled_expire_job
    @campaign
  end

  private

  # The agent-facing informational OpsNotif is not tied by `subject` — it is
  # a plain notice with the deadline text. Matched by creator + audience +
  # a creation window near the campaign's own so we don't erase unrelated
  # notices that happen to point at the same accounts.
  def cleanup_agent_notice
    OperationsNotification
      .where(created_by_id: @campaign.created_by_id, audience_type: :agents, subject_id: nil)
      .where(created_at: @campaign.created_at..(@campaign.created_at + 5.seconds))
      .find_each(&:soft_delete!)
  end

  # Sidekiq keeps the scheduled job in a sorted set until its `at` fires.
  # Best-effort — a job that already ran and did nothing (its
  # `status_open?` guard already covers a closed campaign) is fine.
  def drop_scheduled_expire_job
    Sidekiq::ScheduledSet.new.each do |entry|
      next unless entry.klass == 'Terms::ExpireCampaignJob'

      wrapper = entry.args.first
      job_args = wrapper.is_a?(Hash) ? wrapper['arguments'] : entry.args
      entry.delete if job_args.first.to_i == @campaign.id
    end
  rescue StandardError => e
    Rails.logger.warn("[terms] failed to drop scheduled expire job for campaign #{@campaign.id}: #{e.message}")
  end
end
