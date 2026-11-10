# The period picked on the Início page, the one right before it (same length,
# for the "vs." comparison) and the points of each card's trend line:
# a day per point up to 14 days, a week up to 90, a month beyond. A single
# day ("Hoje") draws the 5 days before it, since one point says nothing.
class V2::Reports::Home::Period
  SINGLE_DAY_TREND = 5

  attr_reader :range, :previous

  def initialize(since:, until_time:)
    @range = since...until_time
    @previous = (since - length)...since
  end

  def granularity
    return :day if length <= 14.days
    return :week if length <= 90.days

    :month
  end

  def buckets
    @buckets ||= case granularity
                 when :day then day_buckets
                 when :week then step_buckets { |start| start + 7.days }
                 else step_buckets { |start| start.next_month.beginning_of_month }
                 end
  end

  # Everything the cards read: the trend line, the period and the one before.
  def window
    [buckets.first.first, previous.first].min...range.last
  end

  private

  def length
    range.last - range.first
  end

  def day_buckets
    first_day = range.first.beginning_of_day
    first_day -= (SINGLE_DAY_TREND - 1).days if length <= 1.day
    step_buckets(first_day) { |start| start.beginning_of_day + 1.day }
  end

  def step_buckets(start = range.first)
    buckets = []
    while start < range.last
      finish = [yield(start), range.last].min
      buckets << (start...finish)
      start = finish
    end
    buckets
  end
end
