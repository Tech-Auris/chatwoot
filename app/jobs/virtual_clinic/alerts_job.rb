# Every 15 minutes: the alert rules of every account with the Clínica virtual.
class VirtualClinic::AlertsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.where(virtual_clinic_enabled: true).find_each do |account|
      VirtualClinic::AlertChecker.new(account).perform
    rescue StandardError => e
      Rails.logger.error("[VirtualClinic] alerts of account #{account.id} failed: #{e.class} #{e.message}")
    end
  end
end
