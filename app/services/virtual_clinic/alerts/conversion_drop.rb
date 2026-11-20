# Helena: the conversion of the last 7 days (appointments / leads) is 20%
# or more below the average of the 4 weeks before. Needs some volume, so a
# quiet week of 3 leads does not ring the bell.
class VirtualClinic::Alerts::ConversionDrop < VirtualClinic::Alerts::DailyRule
  DROP = 0.8
  MIN_LEADS = 5

  def payload
    week = rate(*numbers(@now - 7.days, @now).values_at(:leads, :appointments))
    return if week.nil?

    average = earlier_average
    return if average.nil? || average.zero? || week >= average * DROP

    { rate: week.round(1), average: average.round(1) }
  end

  private

  def earlier_average
    rates = (1..4).filter_map { |back| rate(*numbers(@now - (7 * (back + 1)).days, @now - (7 * back).days).values_at(:leads, :appointments)) }
    rates.sum / rates.size if rates.any?
  end

  def rate(leads, appointments)
    appointments * 100.0 / leads if leads >= MIN_LEADS
  end
end
