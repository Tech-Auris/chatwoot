# The day summary at the top of the Início page. It ignores the page filters:
# it is always today, in the account's timezone, over every caixa in view.
class V2::Reports::Home::TodayBuilder
  # A lead counts as waiting once their last message sits unanswered this long,
  # and stops counting after a day: an open conversation forgotten for weeks
  # is not someone waiting for an answer now.
  WAITING_AFTER = 10.minutes
  WAITING_UP_TO = 24.hours
  WAITING_LIST_LIMIT = 50

  def initialize(scope:)
    @scope = scope
  end

  # Cards with a drill-down: what `entries` answers for.
  DRILLABLE = %w[new_leads_today booked_today tomorrow].freeze

  def build
    {
      new_leads: new_leads.count,
      booked: booked.distinct.count(:conversation_id),
      waiting: { count: waiting.count, conversations: waiting_list },
      tomorrow: tomorrow
    }
  end

  # `[conversation_id, time, detail]` behind a card, for its drill-down.
  def entries(metric)
    case metric
    when 'new_leads_today' then new_leads.pluck(:id, :created_at).map { |id, at| [id, at, nil] }
    when 'booked_today' then booked.pluck(:conversation_id, :created_at, :user_id)
    when 'tomorrow' then tomorrow_appointments.pluck(:conversation_id, :scheduled_for, :status)
    end
  end

  private

  attr_reader :scope

  delegate :conversations, :zone, to: :scope

  def today
    zone.now.all_day
  end

  def new_leads
    conversations.where(created_at: today)
  end

  def booked
    scope.stage_changes(scope.scheduling_stage_names).where(created_at: today)
  end

  def tomorrow_appointments
    Appointment.open.where(conversation_id: conversations.select(:id), scheduled_for: zone.now.tomorrow.all_day)
  end

  # Last message from the lead, unanswered by the AI or the team for over 10
  # minutes (an answer clears `waiting_since`), and no follow-up on its way.
  def waiting
    conversations.open
                 .where(conversations: { waiting_since: WAITING_UP_TO.ago...WAITING_AFTER.ago })
                 .where.not(id: FollowUp.outcome_waiting.select(:conversation_id))
  end

  def waiting_list
    waiting.includes(:contact, :inbox, :assignee).order(:waiting_since).limit(WAITING_LIST_LIMIT).map do |conversation|
      {
        id: conversation.display_id,
        contact_name: conversation.contact&.name,
        contact_phone: conversation.contact&.phone_number,
        inbox_name: conversation.inbox.name,
        assignee_name: conversation.assignee&.name,
        origem: conversation.origem,
        waiting_since: conversation.waiting_since.to_i
      }
    end
  end

  def tomorrow
    { scheduled: tomorrow_appointments.count, confirmed: tomorrow_appointments.where(status: :confirmed).count }
  end
end
