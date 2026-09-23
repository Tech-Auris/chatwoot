# Holds a proposal until a date, and mirrors that date onto the ClickUp task so
# the deal carries its own deadline where the sales team already works.
#
# The reservation is recorded here even when ClickUp refuses: a hiccup on their
# side must not block a sale in front of a customer. What failed is written to
# the trail and reported back, so nobody assumes the task was updated.
class Sales::ReserveQuoteService
  RESERVATION_TAG = 'reserva'.freeze
  # The ClickUp status the deal moves to when the reservation is taken.
  # Lowercase, with the tilde — matches the naming convention the sales
  # pipeline uses (see the existing status values in `sales_quotes`).
  RESERVATION_CLICKUP_STATUS = 'negociação'.freeze

  Result = Struct.new(:quote, :clickup_synced, :clickup_error, keyword_init: true)

  def initialize(quote:, reserved_until:, user: nil, client: nil)
    @quote = quote
    @reserved_until = reserved_until
    @user = user
    @client = client
  end

  # Marker key used to tell the reservations sync that this quote just had
  # its `reserved_until` written locally. See `LOCAL_WRITE_WINDOW`.
  def self.local_write_marker_key(quote_id)
    "sales/quote_reserved_until_touched_at/#{quote_id}"
  end

  # The prospect cache the sync reads from lives for 5 minutes; the marker
  # has to cover at least that so a page load in the window keeps our
  # freshly-written deadline.
  LOCAL_WRITE_WINDOW = 5.minutes

  def perform
    raise ArgumentError, 'Informe a data de vencimento da reserva' if reserved_until.blank?
    raise ArgumentError, 'A data da reserva precisa estar no futuro' if reserved_until.past?

    renewal = quote.reserved?
    quote.update!(reserved_until: reserved_until, status: :reserved)
    mark_local_write
    mirror_deadline_to_pending_terms

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

    # The deadline lives in the dedicated "Vencimento da Reserva" custom
    # field so it can move independently from the task's native due_date
    # (which the sales team uses for the story deadline). Epoch is
    # normalised to midnight in the sales-team timezone — ClickUp renders
    # this field as a date, so UTC midnight would slide back a day for a
    # reader east of UTC.
    client.update_task(quote.clickup_task_id, status: RESERVATION_CLICKUP_STATUS)
    client.set_custom_field(
      quote.clickup_task_id,
      Sales::ClickupProspectSearchService::RESERVATION_DUE_FIELD_ID,
      reserved_until.in_time_zone(Sales::ClickupProspectSearchService::SALES_TIMEZONE).beginning_of_day.to_i * 1000
    )
    quote.update_column(:clickup_status, RESERVATION_CLICKUP_STATUS) # rubocop:disable Rails/SkipsModelValidations
    client.add_tag(quote.clickup_task_id, RESERVATION_TAG)
    post_reservation_comment
    invalidate_prospect_cache
    nil
  rescue Integrations::Clickup::Client::Error => e
    e.message
  end

  # The Reservations page reads ClickUp through a 5-minute list cache, so a
  # renewal that just wrote to ClickUp can be overwritten by the very next
  # page load reading the stale cached deadline. Invalidate the cache here
  # so the next sync pass fetches fresh data. Belt-and-suspenders lives in
  # `Sales::ReservationSyncService`, which also refuses to overwrite a
  # very recently written deadline (via `mark_local_write`).
  def invalidate_prospect_cache
    list_id = GlobalConfig.get('CLICKUP_PIPELINE_LIST_ID')['CLICKUP_PIPELINE_LIST_ID'].presence
    return if list_id.blank?

    Rails.cache.delete("sales/clickup_prospects/#{list_id}")
  end

  # Set right after the DB write and before any external call so a concurrent
  # `ReservationSyncService.perform` (running for another operator's Reservations
  # page load) does not read a stale cached ClickUp deadline and overwrite the
  # freshly-written value.
  def mark_local_write
    Rails.cache.write(self.class.local_write_marker_key(quote.id), true, expires_in: LOCAL_WRITE_WINDOW)
  end

  # The `signature` terms acceptance for this quote inherits the reservation's
  # deadline — the prospect has until the reservation expires to sign. A
  # renewal moves both dates together. A row that is already signed stays
  # frozen; the audit trail belongs to whichever version was in effect.
  # Bulk update because the callbacks on TermsAcceptance are about signing,
  # not about deadline moves — no reason to instantiate rows only to mirror a
  # single timestamp.
  def mirror_deadline_to_pending_terms
    quote.terms_acceptances.status_pending.kind_signature.update_all(deadline_at: reserved_until) # rubocop:disable Rails/SkipsModelValidations
  end

  # Posts a comment with the copy-paste WhatsApp message on the task,
  # so the person who handles the handoff has the exact text next to
  # the reservation deadline. Failure here does not fail the sync —
  # the reservation is what matters; the comment is a convenience.
  def post_reservation_comment
    comment = Sales::ReservationMessageBuilder.clickup_comment_for(quote)
    return if comment.blank?

    client.add_comment(quote.clickup_task_id, comment)
  rescue Integrations::Clickup::Client::Error => e
    Rails.logger.warn("[sales] reservation comment not posted: #{e.message}")
  end

  def record_event(renewal, error)
    quote.events.create!(
      user: user,
      event: renewal ? 'reservation_renewed' : 'reserved',
      metadata: { reserved_until: reserved_until.iso8601, clickup_synced: error.nil?, clickup_error: error }.compact
    )
  end
end
