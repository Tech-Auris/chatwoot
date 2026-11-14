# The "IA e atendimento" row of the Início page: first response time, the
# leads the AI took part in and how many of those it handed to the team.
# A handoff is the same record the IA → Humano report lists.
class V2::Reports::Home::AiActivity
  def initialize(scope:, period:)
    @scope = scope
    @period = period
  end

  # `[conversation_id, created_at]` of the leads where the AI sent the patient
  # at least one message.
  def acted_rows
    @acted_rows ||= if ai_user_id
                      scope.conversations.where(created_at: period.window).where(ai_message.arel.exists).pluck(:id, :created_at)
                    else
                      []
                    end
  end

  def handoff
    current = acted_in(period.range)
    previous = acted_in(period.previous)
    handed_off = handed_off_count(current)
    {
      rate: rate(handed_off, current.size),
      previous_rate: rate(handed_off_count(previous), previous.size),
      handed_off: handed_off,
      ai_conversations: current.size
    }
  end

  def response_time
    current = first_responses.where(created_at: period.range)
    {
      average: average(current),
      previous: average(first_responses.where(created_at: period.previous)),
      ai_average: ai_user_id && average(current.where(user_id: ai_user_id)),
      team_average: average(ai_user_id ? current.where.not(user_id: ai_user_id) : current)
    }
  end

  private

  attr_reader :scope, :period

  # Looked up lead by lead in the messages index by account and sender, never
  # touching the table: collecting the AI's messages first scanned the whole
  # messages table and ran past the statement timeout on accounts with many
  # leads. Everything the AI user sends is an outgoing, public message.
  def ai_message
    Message.unscope(:order).where(account_id: scope.account.id, sender_type: 'User', sender_id: ai_user_id)
           .where('messages.conversation_id = conversations.id')
  end

  def acted_in(range)
    acted_rows.select { |_id, time| range.cover?(time) }.map(&:first).uniq
  end

  def handed_off_count(conversation_ids)
    AiAssignmentAttempt.where(conversation_id: conversation_ids).distinct.count(:conversation_id)
  end

  def rate(part, total)
    return nil if total.zero?

    (part * 100.0 / total).round(1)
  end

  def first_responses
    ReportingEvent.where(account_id: scope.account.id, name: 'first_response', conversation_id: scope.conversations.select(:id))
  end

  def average(events)
    events.average(:value)&.round
  end

  def ai_user_id
    Conversation.ai_user_id
  end
end
