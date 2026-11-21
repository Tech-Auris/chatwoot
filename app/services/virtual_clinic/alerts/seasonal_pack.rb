# Helena tells the clinic when a decoration pack arrives (VirtualClinic::
# Season), once per season: until when it lasts and where to find it.
class VirtualClinic::Alerts::SeasonalPack < VirtualClinic::Alerts::DailyRule
  def payload
    season = VirtualClinic::Season.active(@now.to_date).find { |candidate| !candidate[:always] && !announced?(candidate) }
    return unless season

    { season: season[:key], name: I18n.t("virtual_clinic.seasons.#{season[:key]}.name"),
      until: Date.new(@now.year, *season[:to]).strftime('%d/%m'), extra: I18n.t("virtual_clinic.seasons.#{season[:key]}.extra") }
  end

  private

  def announced?(season)
    start = @now.change(month: season[:from].first, day: season[:from].last).beginning_of_day
    account.virtual_clinic_alerts.where(rule: self.class.key, created_at: start..).exists?(['payload @> ?', { season: season[:key] }.to_json])
  end
end
