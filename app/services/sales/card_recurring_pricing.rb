# What the recurring card charges on a long plan (semiannual / annual).
#
# The first cycle is the agreed total — the one the contract states, setup fee
# included — split into one charge per month of the plan, with the cents that
# do not divide on the first charge. Once that cycle is over the subscription
# renews for the same period with the subscription lines only, at list price:
# the proposal's discount held for the first cycle, and the setup fee was a
# one-off.
module Sales::CardRecurringPricing
  module_function

  def charge_for(quote)
    quote.effective_total_amount / installments(quote)
  end

  def residue_for(quote)
    quote.effective_total_amount % installments(quote)
  end

  def renewal_charge_for(quote)
    recurring = quote.items.select { |item| item.recurring_interval.present? }
    base = recurring.empty? ? quote.effective_total_amount : recurring.sum(&:total_amount)
    base / installments(quote)
  end

  # The monthly charge recurs; the leftover cents ride on the first invoice
  # only. The renewal price is planned by Sales::CardRecurringScheduleService
  # once the subscription exists.
  def line_items(quote)
    name = "AurisChat — #{quote.prospect_name}"
    lines = [line(quote, name, charge_for(quote), recurring: true)]
    residue = residue_for(quote)
    lines << line(quote, "#{name} (ajuste de centavos)", residue, recurring: false) if residue.positive?
    lines
  end

  def subscription_payload(quote)
    { mode: 'subscription',
      subscription_data: { metadata: { sales_quote_id: quote.id, installments: installments(quote) } } }
  end

  def installments(quote)
    Sales::CheckoutService.installments_for(quote.billing_cycle)
  end

  def line(quote, name, amount, recurring:)
    price_data = { currency: quote.currency, unit_amount: amount, product_data: { name: name } }
    price_data[:recurring] = { interval: 'month' } if recurring
    { quantity: 1, price_data: price_data }
  end
end
