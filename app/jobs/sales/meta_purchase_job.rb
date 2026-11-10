# Sends the Meta Purchase of a paid sale (Sales::MetaPurchaseService). A Meta
# or network error is retried with a growing wait; giving up lands on the
# proposal's history and never touches the payment or the account.
class Sales::MetaPurchaseJob < ApplicationJob
  queue_as :low

  retry_on Sales::MetaPurchaseService::DeliveryError, wait: :polynomially_longer, attempts: 8 do |job, error|
    quote = SalesQuote.find_by(id: job.arguments.first)
    quote&.events&.create!(event: 'meta_purchase_failed', metadata: { error: error.message.truncate(500) })
  end

  def perform(quote_id, paid_at)
    quote = SalesQuote.find_by(id: quote_id)
    return if quote.nil? || quote.events.exists?(event: 'meta_purchase_sent')

    Sales::MetaPurchaseService.new(quote: quote, paid_at: Time.zone.at(paid_at)).perform
  rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
    raise Sales::MetaPurchaseService::DeliveryError, "#{e.class}: #{e.message}"
  end
end
