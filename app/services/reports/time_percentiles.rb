# Time metrics in the reports (first response, resolution, reply time) are the
# 95th percentile, with the median shown in the hint. An average gets dragged
# by a handful of extreme conversations (e.g. one left unanswered for days).
module Reports::TimePercentiles
  P95 = 0.95
  MEDIAN = 0.5

  module_function

  def sql(fraction, column, event_name: nil)
    expression = "PERCENTILE_CONT(#{fraction}) WITHIN GROUP (ORDER BY #{column})"
    event_name ? "#{expression} FILTER (WHERE name = '#{event_name}')" : expression
  end
end
