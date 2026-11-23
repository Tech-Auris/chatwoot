# Luciano's numbers for a period, from Marketing → Analytics: the ads that
# brought conversations or spent, their leads and appointments, the spend and
# what one appointment cost (in reais; nil without spend or appointments).
class VirtualClinic::MarketingNumbers
  def initialize(account, from, to)
    @rows = V2::Reports::CampaignAnalyticsBuilder.new(account: account, params: { since: from.to_i.to_s, until: to.to_i.to_s }).build
  end

  def to_h
    spend = sum(:spend_cents)
    appointments = sum(:scheduled_count)
    { active_campaigns: @rows.count { |row| (row[:conversations_count].to_i + row[:spend_cents].to_i).positive? },
      leads: sum(:conversations_count), appointments: appointments, spend: (spend / 100.0).round(2),
      cost_per_appointment: appointments.positive? && spend.positive? ? (spend / 100.0 / appointments).round(2) : nil }
  end

  private

  def sum(key)
    @rows.sum { |row| row[key].to_i }
  end
end
