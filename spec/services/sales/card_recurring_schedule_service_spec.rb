require 'rails_helper'

RSpec.describe Sales::CardRecurringScheduleService do
  let(:client) { instance_double(Integrations::Stripe::Client) }
  let(:quote) do
    create(:sales_quote, billing_cycle: :semiannual, total_amount: 738_000, payment_method: :card_recurring,
                         stripe_subscription_id: 'sub_1')
  end
  let(:started_at) { Time.zone.parse('2026-11-10 12:00') }
  let(:subscription) do
    Stripe::Subscription.construct_from(id: 'sub_1', schedule: nil,
                                        items: { data: [{ price: { id: 'price_first', product: 'prod_1' } }] })
  end

  before do
    create(:sales_quote_item, sales_quote: quote, name: 'Plano Auris', unit_amount: 600_000, recurring_interval: 'month')
    create(:sales_quote_item, sales_quote: quote, name: 'Implantação', unit_amount: 138_000, recurring_interval: nil)
    allow(client).to receive(:retrieve_subscription).with('sub_1').and_return(subscription)
    allow(client).to receive(:create_subscription_schedule_from).with('sub_1')
                                                                .and_return(Stripe::SubscriptionSchedule.construct_from(
                                                                              id: 'sub_sched_1', phases: [{ start_date: started_at.to_i }]
                                                                            ))
    allow(client).to receive(:update_subscription_schedule)
  end

  def perform
    described_class.new(quote: quote, client: client).perform
  end

  # Six charges at the first-cycle price, then the renewal price (no setup
  # fee) for another six months, and released to keep renewing after that.
  it 'plans the first cycle and the renewal' do
    perform

    expect(client).to have_received(:update_subscription_schedule).with(
      'sub_sched_1',
      { end_behavior: 'release',
        phases: [
          { items: [{ price: 'price_first', quantity: 1 }], start_date: started_at.to_i, end_date: (started_at + 6.months).to_i },
          { items: [{ price_data: { currency: 'brl', product: 'prod_1', unit_amount: 100_000, recurring: { interval: 'month' } },
                      quantity: 1 }],
            end_date: (started_at + 12.months).to_i }
        ] }
    )
    expect(quote.events.find_by(event: 'card_recurring_scheduled').metadata['renewal_amount']).to eq(100_000)
  end

  # The job is retried; a subscription already planned is left alone.
  it 'does nothing when the subscription already has a schedule' do
    subscription['schedule'] = 'sub_sched_1'

    perform

    expect(client).not_to have_received(:create_subscription_schedule_from)
  end
end
