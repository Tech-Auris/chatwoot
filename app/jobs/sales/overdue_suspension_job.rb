# Suspends the account of a recurring-card customer whose Stripe charge has
# been unpaid for OVERDUE_DAYS. Stripe keeps retrying and warning the customer
# meanwhile; the account comes back on its own when the invoice is paid (see
# Webhooks::Commercial::StripeController).
class Sales::OverdueSuspensionJob < ApplicationJob
  queue_as :low

  OVERDUE_DAYS = 30

  def perform
    overdue.find_each do |quote|
      quote.account.suspended!
      quote.events.create!(event: 'account_suspended', metadata: { account_id: quote.account_id,
                                                                   overdue_since: quote.payment_overdue_since })
    end
  end

  private

  def overdue
    SalesQuote.payment_method_card_recurring
              .where(payment_overdue_since: ..OVERDUE_DAYS.days.ago)
              .joins(:account).where.not(accounts: { status: :suspended })
              .includes(:account)
  end
end
