# Runs Sales::ClickupCrmSyncService off the request cycle so a ClickUp hiccup
# does not delay the customer or block the sale from being marked paid.
# Sidekiq's default backoff retries transient failures for us.
#
# `phase` picks which side of the sync to run: :paid_fields writes the fourteen
# custom fields the finance checklist covers; :closed flips the pipeline task
# to "negócio fechado".
class Sales::ClickupCrmSyncJob < ApplicationJob
  queue_as :low

  def perform(quote_id, phase)
    quote = SalesQuote.find_by(id: quote_id)
    return if quote.blank?

    service = Sales::ClickupCrmSyncService.new(quote: quote)
    case phase.to_s
    when 'paid_fields' then service.sync_paid_fields!
    when 'closed' then service.mark_closed!
    end
  end
end
