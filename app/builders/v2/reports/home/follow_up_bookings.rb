# "Agendamentos após follow-up": bookings of leads who got a follow-up before
# booking, each under the last follow-up sent before it (1st, 2nd, 3rd or
# later). Besides the card's numbers it lists the conversations of the period,
# for the detail dialog.
class V2::Reports::Home::FollowUpBookings
  # `bookings` are `[conversation_id, booked_at, ..., booked_by_id]` rows.
  def initialize(bookings:, period:)
    @bookings = bookings
    @period = period
  end

  # `[conversation_id, booked_at]` for every booking that came after a follow-up.
  def rows
    entries.map { |entry| entry.first(2) }
  end

  def details
    { steps: steps, conversations: conversations }
  end

  private

  attr_reader :bookings, :period

  # `[conversation_id, booked_at, step, booked_by_id]`
  def entries
    @entries ||= bookings.filter_map do |row|
      step = last_step(row.first, row.second)
      [row.first, row.second, step, row.last] if step
    end
  end

  # Each conversation counts once in the period, under its latest booking.
  def latest_in_period
    @latest_in_period ||= entries.select { |entry| period.range.cover?(entry.second) }
                                 .group_by(&:first).values.map { |group| group.max_by(&:second) }
  end

  def steps
    found = latest_in_period.map(&:third)
    { first: found.count(1), second: found.count(2), third_or_more: found.count { |step| step >= 3 } }
  end

  def conversations
    found = Conversation.where(id: latest_in_period.map(&:first)).includes(:contact, :inbox).index_by(&:id)
    names = User.where(id: latest_in_period.filter_map(&:last)).pluck(:id, :name).to_h
    latest_in_period.sort_by { |entry| -entry.second.to_i }.map do |id, booked_at, step, booked_by_id|
      conversation_row(found[id], booked_at, step, names[booked_by_id])
    end
  end

  def conversation_row(conversation, booked_at, step, booked_by)
    {
      id: conversation.display_id, contact_name: conversation.contact&.name, contact_phone: conversation.contact&.phone_number,
      inbox_name: conversation.inbox.name, origem: conversation.origem, booked_by: booked_by,
      booked_at: booked_at.to_i, step: step
    }
  end

  def last_step(conversation_id, booked_at)
    follow_ups[conversation_id]&.select { |_step, sent_at| sent_at <= booked_at }&.max_by(&:last)&.first
  end

  def follow_ups
    @follow_ups ||= FollowUp.where(conversation_id: bookings.map(&:first).uniq)
                            .where.not(delivery_status: :failed)
                            .pluck(:conversation_id, :step, :created_at)
                            .group_by(&:first)
                            .transform_values { |rows| rows.map { |_id, step, at| [step, at] } }
  end
end
