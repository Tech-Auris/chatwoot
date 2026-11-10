# Plans the renewal of a recurring-card subscription once Stripe created it
# (Sales::CardRecurringScheduleService). A Stripe hiccup is retried; the
# payment and the account never wait on it.
class Sales::CardRecurringScheduleJob < ApplicationJob
  queue_as :default

  retry_on Integrations::Stripe::Client::ProviderUnavailable, wait: :polynomially_longer, attempts: 8

  def perform(quote_id)
    quote = SalesQuote.find_by(id: quote_id)
    return if quote.nil?

    Sales::CardRecurringScheduleService.new(quote: quote).perform
  end
end
