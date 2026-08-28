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
    changes[:reserved_until] = deadline if deadline.present? && deadline != quote.reserved_until

    quote.update!(changes)
    record_deadline_change(quote, deadline) if changes.key?(:reserved_until)
  end

  # ClickUp reports dates in epoch milliseconds.
  def deadline_from(task)
    return nil if task[:due_date].blank?

    Time.zone.at(task[:due_date].to_i / 1000).change(usec: 0)
  end

  def record_deadline_change(quote, deadline)
    quote.events.create!(event: 'deadline_synced_from_clickup', metadata: { reserved_until: deadline.iso8601 })
  end
end
