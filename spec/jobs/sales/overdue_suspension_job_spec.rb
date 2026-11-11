require 'rails_helper'

RSpec.describe Sales::OverdueSuspensionJob do
  let(:account) { create(:account) }
  let(:quote) do
    create(:sales_quote, billing_cycle: :annual, payment_method: :card_recurring, account: account, status: :converted)
  end

  it 'suspends the account once the charge is 30 days overdue' do
    quote.update!(payment_overdue_since: 30.days.ago)

    described_class.perform_now

    expect(account.reload).to be_suspended
    expect(quote.events.find_by(event: 'account_suspended')).to be_present
  end

  it 'leaves the account alone before that' do
    quote.update!(payment_overdue_since: 29.days.ago)

    described_class.perform_now

    expect(account.reload).to be_active
  end

  it 'only looks at the recurring card' do
    quote.update!(payment_method: :card, payment_overdue_since: 40.days.ago)

    described_class.perform_now

    expect(account.reload).to be_active
  end
end
