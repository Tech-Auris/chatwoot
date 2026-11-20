# 8h (São Paulo): "Bom dia da Helena" for the clinics that turned it on.
class VirtualClinic::DailySummaryJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.where(virtual_clinic_enabled: true).find_each do |account|
      VirtualClinic::AlertChecker.new(account, rules: [VirtualClinic::Alerts::DailySummary]).perform
    end
  end
end
