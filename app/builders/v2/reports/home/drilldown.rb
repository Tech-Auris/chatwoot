# The conversations behind one card of the Início page, a page at a time: one
# row per conversation, at its latest entry in the period, newest first. The
# entries come from the builder that counts the card, so the list always adds
# up to the number on screen.
class V2::Reports::Home::Drilldown
  PER_PAGE = 50

  class UnknownMetric < StandardError; end

  def initialize(today:, metrics:, period:, metric:, page:)
    @today = today
    @metrics = metrics
    @period = period
    @metric = metric.to_s
    @page = [page.to_i, 1].max
  end

  def build
    shown = latest_entries.slice((page - 1) * PER_PAGE, PER_PAGE) || []
    { rows: rows(shown), meta: { current_page: page, per_page: PER_PAGE, total_count: latest_entries.size } }
  end

  private

  attr_reader :today, :metrics, :period, :metric, :page

  def entries
    return today.entries(metric) if V2::Reports::Home::TodayBuilder::DRILLABLE.include?(metric)
    raise UnknownMetric unless V2::Reports::Home::MetricsBuilder::DRILLABLE.include?(metric)

    metrics.entries(metric).select { |_id, at| period.range.cover?(at) }
  end

  def latest_entries
    @latest_entries ||= entries.group_by(&:first).values.map { |group| group.max_by(&:second) }
                               .sort_by { |entry| -entry.second.to_i }
  end

  def rows(shown)
    conversations = Conversation.where(id: shown.map(&:first)).includes(:contact, :inbox).index_by(&:id)
    shown.map { |id, at, detail| row(conversations[id], at, detail) }
  end

  def row(conversation, at, detail)
    {
      id: conversation.display_id, contact_name: conversation.contact&.name, contact_phone: conversation.contact&.phone_number,
      inbox_name: conversation.inbox.name, origem: conversation.origem, at: at.to_i, detail: readable(detail)
    }
  end

  # Who booked or moved the lead comes as a user id and the loss reason as its
  # id; the follow-up step and the appointment status go as they are.
  def readable(detail)
    return loss_reason_names[detail] if metric == 'losses'
    return detail unless user_detail?

    user_names[detail]
  end

  def loss_reason_names
    @loss_reason_names ||= LossReason.where(id: latest_entries.filter_map(&:third)).pluck(:id, :name).to_h
  end

  def user_detail?
    %w[appointments off_hours_appointments booked_today no_shows attendances].include?(metric)
  end

  def user_names
    @user_names ||= User.where(id: latest_entries.filter_map(&:third)).pluck(:id, :name).to_h
  end
end
