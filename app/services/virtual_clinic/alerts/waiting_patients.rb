# Clara: patients who wrote and got no answer for more than X minutes
# (30 by default). Only today's waits: an old conversation left open is not
# news.
class VirtualClinic::Alerts::WaitingPatients < VirtualClinic::Alerts::Rule
  SHOWN = 5

  def payload
    minutes = setting(:waiting_minutes, 30).to_i
    scope = account.conversations.open.where(waiting_since: 1.day.ago..minutes.minutes.ago)
    count = scope.count
    return if count.zero?

    { count: count, minutes: minutes, patients: scope.order(:waiting_since).limit(SHOWN).includes(:contact).map do |conversation|
      { name: conversation.contact&.name, conversation_id: conversation.display_id, waiting_minutes: minutes_since(conversation.waiting_since) }
    end }
  end
end
