# Brings the reservations in line with ClickUp before they are listed.
#
# ClickUp owns the deal: the status and the deadline are changed there, never
# here. Rather than a call per row, the pipeline the search service already
# caches is read once and the differences are applied.
class Sales::ReservationSyncService
  def initialize(quotes:, search_service: nil)
    @quotes = quotes
    @search_service = search_service
  end

  def perform
    quotes.each { |quote| sync(quote) }
    quotes
  rescue Sales::ClickupProspectSearchService::NotConfigured, Integrations::Clickup::Client::Error => e
    # A report that cannot reach ClickUp still shows what we know, with the
    # mirror as stale as it was.
    Rails.logger.info("[sales] reservations not synced: #{e.message}")
    quotes
  end

  private

  attr_reader :quotes

  def search_service
    @search_service ||= Sales::ClickupProspectSearchService.new
  end

  def sync(quote)
    task = search_service.find(quote.clickup_task_id)
    return if task.blank?

    changes = { clickup_status: task[:status], clickup_status_synced_at: Time.current }
    deadline = deadline_from(task)
    changes[:reserved_until] = deadline if deadline_changed?(quote, deadline)

    quote.update!(changes)
    record_deadline_change(quote, deadline) if changes.key?(:reserved_until)
  end

  # `ReserveQuoteService` writes a marker to the cache right after updating
  # `reserved_until` locally. The marker lives longer than the prospect-list
  # cache, so a page load reading a stale ClickUp deadline within that
  # window keeps our local truth instead of reverting.
  def locally_touched?(quote)
    Rails.cache.exist?(Sales::ReserveQuoteService.local_write_marker_key(quote.id))
  end

  # Compare by São Paulo calendar day, not by absolute Time. The value the
  # controller stores is `.end_of_day` in the app timezone (UTC), while the
  # value we mirror to ClickUp is São Paulo midnight — the two Times differ
  # by a few hours but represent the same day for the sales team.
  def deadline_changed?(quote, deadline)
    return false if deadline.blank?
    return false if locally_touched?(quote)

    deadline_day(deadline) != deadline_day(quote.reserved_until)
  end

  def deadline_day(time)
    time&.in_time_zone(Sales::ClickupProspectSearchService::SALES_TIMEZONE)&.to_date
  end

  # ClickUp reports dates in epoch milliseconds — normalised to São Paulo
  # end-of-day so a locally-stored deadline still means "reserved through
  # this whole day" in the sales-team timezone.
  def deadline_from(task)
    return nil if task[:due_date].blank?

    Time.zone.at(task[:due_date].to_i / 1000).in_time_zone(Sales::ClickupProspectSearchService::SALES_TIMEZONE).end_of_day
  end

  def record_deadline_change(quote, deadline)
    quote.events.create!(event: 'deadline_synced_from_clickup', metadata: { reserved_until: deadline.iso8601 })
  end
end
