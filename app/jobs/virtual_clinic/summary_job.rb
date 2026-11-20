# Every hour: Helena's summaries due now (each person's daily, weekly and
# monthly choices at their hour, in the clinic's time zone). Only
# administrators and managers get them: they have her numbers.
class VirtualClinic::SummaryJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.where(virtual_clinic_enabled: true).find_each do |account|
      now = Time.current.in_time_zone(account.reporting_timezone.presence || 'America/Sao_Paulo')
      I18n.with_locale(account.locale) { send_due(account, now) }
    end
  end

  private

  def send_due(account, now)
    managers = account.account_users.where(role: %i[administrator manager]).select(:user_id)
    account.virtual_clinic_summaries.where(hour: now.hour, user_id: managers).includes(:user, :account).find_each do |summary|
      summary.due_periods(now).each { |period| VirtualClinic::SummarySender.new(summary, period, now).perform }
    end
  end
end
