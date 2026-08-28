# Holds a proposal until a date, and mirrors that date onto the ClickUp task so
# the deal carries its own deadline where the sales team already works.
#
# The reservation is recorded here even when ClickUp refuses: a hiccup on their
# side must not block a sale in front of a customer. What failed is written to
# the trail and reported back, so nobody assumes the task was updated.
class Sales::ReserveQuoteService
  RESERVATION_TAG = 'reserva'.freeze

  Result = Struct.new(:quote, :clickup_synced, :clickup_error, keyword_init: true)

  def initialize(quote:, reserved_until:, user: nil, client: nil)
    @quote = quote
    @reserved_until = reserved_until
    @user = user
    @client = client
  end

  def perform
    raise ArgumentError, 'Informe a data de vencimento da reserva' if reserved_until.blank?
    raise ArgumentError, 'A data da reserva precisa estar no futuro' if reserved_until.past?

    renewal = quote.reserved?
    quote.update!(reserved_until: reserved_until, status: :reserved)

    error = sync_clickup
    record_event(renewal, error)

    Result.new(quote: quote, clickup_synced: error.nil?, clickup_error: error)
  end

  private

  attr_reader :quote, :reserved_until, :user

  def client
    @client ||= Integrations::Clickup::Client.new
  end

  def sync_clickup
    return 'ClickUp não está configurado' unless client.configured?

    client.update_task(quote.clickup_task_id, due_date: reserved_until.to_i * 1000, due_date_time: true)
    client.add_tag(quote.clickup_task_id, RESERVATION_TAG)
    nil
  rescue Integrations::Clickup::Client::Error => e
    e.message
  end

  def record_event(renewal, error)
    quote.events.create!(
      user: user,
      event: renewal ? 'reservation_renewed' : 'reserved',
      metadata: { reserved_until: reserved_until.iso8601, clickup_synced: error.nil?, clickup_error: error }.compact
    )
  end
end
