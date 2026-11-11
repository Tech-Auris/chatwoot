# The recurring card charges the proposal's total split by the months of the
# plan, then renews for the same period at the renewal price — list price, no
# setup fee (Sales::CardRecurringPricing.renewal_charge_for). Stripe Checkout only
# creates a plain subscription, so the change of price is planned here with a
# subscription schedule:
#
#   phase 1: the first-cycle price, for the N months of the plan
#   phase 2: the renewal price, for another N months
#
# and released afterwards, so the subscription keeps renewing at the renewal
# price until somebody cancels it.
class Sales::CardRecurringScheduleService
  def initialize(quote:, client: nil)
    @quote = quote
    @client = client || Integrations::Stripe::Client.new
  end

  # Runs again when the job is retried; a subscription that already has a
  # schedule was planned on a previous run.
  def perform
    subscription = client.retrieve_subscription(quote.stripe_subscription_id)
    return if subscription['schedule'].present?

    schedule = client.create_subscription_schedule_from(subscription['id'])
    client.update_subscription_schedule(schedule['id'], phases_for(schedule, subscription))
    quote.events.create!(event: 'card_recurring_scheduled',
                         metadata: { schedule_id: schedule['id'], renewal_amount: renewal_amount })
  end

  private

  attr_reader :quote, :client

  def phases_for(schedule, subscription)
    start = Time.zone.at(schedule['phases'][0]['start_date'])
    price = subscription['items']['data'][0]['price']
    {
      end_behavior: 'release',
      phases: [
        { items: [{ price: price['id'], quantity: 1 }], start_date: start.to_i, end_date: (start + months).to_i },
        { items: [{ price_data: renewal_price(price), quantity: 1 }], end_date: (start + (months * 2)).to_i }
      ]
    }
  end

  def renewal_price(price)
    { currency: quote.currency, product: price['product'], unit_amount: renewal_amount, recurring: { interval: 'month' } }
  end

  def renewal_amount
    Sales::CardRecurringPricing.renewal_charge_for(quote)
  end

  def months
    Sales::CheckoutService.installments_for(quote.billing_cycle).months
  end
end
