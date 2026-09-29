# Sends one of the proposal's WhatsApp messages to the lead and records the
# outcome on the proposal's trail (the Reservations grid shows it):
#   reservation       — the link + access code, when the seller reserves
#   last_day_reminder — on the reservation's last day (Sales::ReservationReminderJob)
#
# Not retried: a failure (no phone, inbox not configured, WhatsApp down) is
# recorded for the seller to follow up, instead of the lead getting the same
# message twice later on.
class Sales::LeadWhatsappJob < ApplicationJob
  queue_as :default

  KINDS = %w[reservation last_day_reminder].freeze

  def perform(quote_id, kind)
    quote = SalesQuote.find(quote_id)
    content = message_for(quote, kind)
    return record(quote, kind, 'failed', error: 'Mensagem indisponível (reserva sem link ou código)') if content.blank?

    conversation = Sales::LeadWhatsappMessenger.new(quote: quote, content: content).perform
    record(quote, kind, 'sent', conversation_id: conversation.display_id, account_id: conversation.account_id)
  rescue StandardError => e
    raise if quote.nil?

    Rails.logger.error("[Sales::LeadWhatsappJob] quote #{quote_id} #{kind}: #{e.class} #{e.message}")
    record(quote, kind, 'failed', error: e.message)
  end

  private

  def message_for(quote, kind)
    case kind
    when 'reservation' then Sales::ReservationMessageBuilder.for_quote(quote)
    when 'last_day_reminder' then Sales::ReservationMessageBuilder.last_day_reminder_for(quote)
    else raise ArgumentError, "unknown message kind #{kind}"
    end
  end

  def record(quote, kind, outcome, extra = {})
    quote.events.create!(
      event: "whatsapp_#{kind}_#{outcome}",
      metadata: extra.merge(reserved_on: quote.reserved_until&.in_time_zone(Sales::ReservationReminderJob::TIME_ZONE)&.to_date&.iso8601)
    )
  end
end
