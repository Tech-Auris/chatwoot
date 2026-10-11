# What the "Webhook de cadastro final" (Settings → Commercial) receives once a
# sale becomes an AurisChat account: the account, the customer who manages it,
# the company and the plan bought. n8n takes it from there — the Drive folders,
# the Supabase client rows. Amounts are in centavos, as everywhere in Sales.
class Sales::AccountCreatedPayload
  EVENT = 'account.created'.freeze

  def initialize(quote:)
    @quote = quote
  end

  def to_h
    {
      event: EVENT,
      sent_at: Time.current.iso8601,
      account: account_data,
      customer: customer_data,
      company: { name: quote.company_name, document: quote.company_document },
      plan: plan_data,
      sale: sale_data
    }
  end

  private

  attr_reader :quote

  def account
    quote.account
  end

  def account_data
    { id: account.id, name: account.name, locale: account.locale, reporting_timezone: account.reporting_timezone,
      created_at: account.created_at.iso8601, url: "#{ENV.fetch('FRONTEND_URL', '')}/app/accounts/#{account.id}/dashboard" }
  end

  def customer_data
    user = account.account_users.manager.first&.user
    { user_id: user&.id, name: quote.prospect_name.presence || user&.name, email: quote.prospect_email,
      phone: quote.prospect_phone, document: quote.prospect_document }
  end

  def plan_data
    {
      billing_cycle: quote.billing_cycle, payment_method: quote.payment_method, currency: quote.currency,
      subtotal_amount: quote.subtotal_amount, discount_amount: quote.effective_discount_amount,
      total_amount: quote.effective_total_amount, charged_amount: quote.effective_charge_amount,
      discount_summary: quote.effective_discount_summary, coupon_id: quote.coupon_id,
      items: quote.items.map { |item| item_data(item) }
    }
  end

  def item_data(item)
    { name: item.name, kind: item.kind, quantity: item.quantity, unit_amount: item.unit_amount,
      recurring_interval: item.recurring_interval, stripe_price_id: item.stripe_price_id }
  end

  def sale_data
    { quote_id: quote.id, clickup_task_id: quote.clickup_task_id, seller: { id: quote.seller_id, name: quote.seller&.name,
                                                                            email: quote.seller&.email } }
  end
end
