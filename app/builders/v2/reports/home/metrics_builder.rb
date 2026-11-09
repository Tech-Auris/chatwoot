# The indicator cards of the Início page. Each counted card returns the total
# of the period, the total of the period before it and one value per point of
# the trend line, all as distinct conversations.
class V2::Reports::Home::MetricsBuilder
  NO_SHOW_STAGE_NAME = V2::Reports::FunnelConversionBuilder::NO_SHOW_STAGE_NAME
  ATTENDANCE_STAGE_NAME = V2::Reports::FunnelConversionBuilder::ATTENDANCE_STAGE_NAME

  def initialize(scope:, period:)
    @scope = scope
    @period = period
  end

  # Cards with a drill-down, and where their entries come from.
  ENTRY_SOURCES = {
    'leads' => :lead_entries, 'off_hours_leads' => :off_hours_lead_entries,
    'appointments' => :booking_entries, 'off_hours_appointments' => :off_hours_booking_entries,
    'follow_up_leads' => :follow_up_rows, 'no_shows' => :no_show_rows, 'attendances' => :attendance_rows
  }.freeze
  DRILLABLE = ENTRY_SOURCES.keys.freeze

  def build
    {
      granularity: period.granularity,
      buckets: period.buckets.map { |bucket| bucket.first.to_i },
      **counted_cards,
      **ai_cards,
      origins: origins,
      **funnel
    }
  end

  # `[conversation_id, time, detail]` behind a counted card over the whole
  # window, for its drill-down: who booked or moved the lead, or the
  # follow-up step.
  def entries(metric)
    send(ENTRY_SOURCES.fetch(metric))
  end

  private

  attr_reader :scope, :period

  def counted_cards
    {
      leads: leads_card,
      appointments: counted(booking_rows.map { |id, time| [id, time] }),
      off_hours_leads: counted(off_hours_lead_rows),
      off_hours_appointments: counted(off_hours_booking_rows.map { |id, booked_at| [id, booked_at] }),
      follow_up_leads: counted(follow_up_rows),
      after_follow_up: after_follow_up,
      no_shows: counted(no_show_rows),
      attendances: counted(attendance_rows)
    }
  end

  # `rows` are `[conversation_id, time]` pairs over the whole window.
  def counted(rows)
    {
      total: distinct_in(rows, period.range),
      previous: distinct_in(rows, period.previous),
      series: period.buckets.map { |bucket| distinct_in(rows, bucket) }
    }
  end

  def distinct_in(rows, range)
    rows.select { |_id, time| range.cover?(time) }.map(&:first).uniq.size
  end

  def leads_card
    @leads_card ||= counted(lead_rows.map { |id, time, _inbox| [id, time] })
  end

  def lead_rows
    @lead_rows ||= scope.conversations.where(created_at: period.window).pluck(:id, :created_at, :inbox_id)
  end

  # `[conversation_id, booked_at, inbox_id, lead_arrived_at, booked_by_id]`
  def booking_rows
    @booking_rows ||= scope.stage_changes(scope.scheduling_stage_names).where(created_at: period.window)
                           .joins('INNER JOIN conversations ON conversations.id = funnel_stage_changes.conversation_id')
                           .pluck(:conversation_id, :created_at, Arel.sql('conversations.inbox_id'),
                                  Arel.sql('conversations.created_at'), :user_id)
  end

  def lead_entries
    lead_rows.map { |id, at| [id, at, nil] }
  end

  def off_hours_lead_entries
    off_hours_lead_rows.map { |id, at| [id, at, nil] }
  end

  def booking_entries
    booking_rows.map { |id, at, *, booked_by| [id, at, booked_by] }
  end

  def off_hours_booking_entries
    off_hours_booking_rows.map { |id, at, *, booked_by| [id, at, booked_by] }
  end

  def no_show_rows
    outcome_rows(NO_SHOW_STAGE_NAME)
  end

  def attendance_rows
    outcome_rows(ATTENDANCE_STAGE_NAME)
  end

  def off_hours_lead_rows
    lead_rows.reject { |_id, time, inbox_id| business_hours.open_at?(inbox_id, time) }.map { |id, time, _inbox| [id, time] }
  end

  # Booked outside business hours, or booked for a lead who arrived outside them.
  def off_hours_booking_rows
    booking_rows.reject { |_id, booked_at, inbox_id, arrived_at| within_hours?(inbox_id, booked_at, arrived_at) }
  end

  def within_hours?(inbox_id, *times)
    times.all? { |time| business_hours.open_at?(inbox_id, time) }
  end

  def business_hours
    @business_hours ||= V2::Reports::Home::BusinessHours.new(
      inboxes: Inbox.where(id: scope.inbox_ids).includes(:working_hours), fallback_zone: scope.zone
    )
  end

  # Leads that got a follow-up sent in the period, with its step.
  def follow_up_rows
    FollowUp.where(conversation_id: scope.conversations.select(:id), created_at: period.window)
            .where.not(delivery_status: :failed)
            .pluck(:conversation_id, :created_at, :step)
  end

  def after_follow_up
    follow_up_bookings = V2::Reports::Home::FollowUpBookings.new(bookings: booking_rows, period: period)
    counted(follow_up_bookings.rows).merge(follow_up_bookings.details)
  end

  # With who moved the lead to that stage.
  def outcome_rows(stage_name)
    scope.stage_changes([stage_name]).where(created_at: period.window).pluck(:conversation_id, :created_at, :user_id)
  end

  # Conversations the AI acted in also come as a share of the period's leads.
  def ai_cards
    ai = V2::Reports::Home::AiActivity.new(scope: scope, period: period)
    acted = counted(ai.acted_rows)
    {
      response_time: ai.response_time,
      ai_conversations: acted.merge(share: share(acted[:total], leads_card[:total]),
                                    previous_share: share(acted[:previous], leads_card[:previous])),
      handoff: ai.handoff
    }
  end

  def share(part, total)
    total.zero? ? nil : (part * 100.0 / total).round(1)
  end

  def origins
    scope.conversations.where(created_at: period.range).group(:origem).count
         .each_with_object(Hash.new(0)) { |(origem, count), acc| acc[origem.presence || none_token] += count }
         .map { |origem, count| { origem: origem, count: count } }
         .sort_by { |row| -row[:count] }
  end

  def none_token
    V2::Reports::FunnelConversionBuilder::ORIGEM_NONE_TOKEN
  end

  def funnel
    report = V2::Reports::FunnelConversionBuilder.new(account: scope.account, params: funnel_params).build
    { funnel: report[:stages], loss_reasons: report[:loss_reasons] }
  end

  def funnel_params
    { since: period.range.first.to_i.to_s, until: period.range.last.to_i.to_s, inbox_ids: scope.inbox_ids, origem: scope.origem }
  end
end
