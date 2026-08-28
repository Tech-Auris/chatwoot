require 'rails_helper'

RSpec.describe Sales::ConvertQuoteService do
  let(:quote) do
    create(:sales_quote, prospect_name: 'Clínica Cinco', prospect_email: 'contato@clinicacinco.com.br',
                         stripe_customer_id: 'cus_1', status: :paid)
  end

  it 'creates the account named after the clinic' do
    result = described_class.new(quote: quote).perform

    expect(result.created).to be true
    expect(result.account.name).to eq('Clínica Cinco')
  end

  it 'links the proposal, the account and the Stripe customer' do
    account = described_class.new(quote: quote).perform.account

    expect(quote.reload).to have_attributes(status: 'converted', account_id: account.id)
    expect(account.reload.stripe_customer_id).to eq('cus_1')
  end

  it 'gives the payer a login on the new account' do
    account = described_class.new(quote: quote).perform.account

    expect(account.users.pluck(:email)).to include('contato@clinicacinco.com.br')
  end

  # Stripe retries webhooks, so this runs more than once for the same sale.
  it 'does not create a second account when it runs again' do
    first = described_class.new(quote: quote).perform

    second = described_class.new(quote: quote.reload).perform

    expect(second.created).to be false
    expect(second.account.id).to eq(first.account.id)
    expect(Account.count).to eq(1)
  end

  # A second sale to the same person, or a customer who already has a login,
  # must not fail on a duplicate e-mail.
  it 'joins an existing user to the new account instead of failing' do
    existing = create(:user, email: 'contato@clinicacinco.com.br')

    account = described_class.new(quote: quote).perform.account

    expect(account.users).to include(existing)
    expect(User.where(email: 'contato@clinicacinco.com.br').count).to eq(1)
  end

  it 'falls back to a name of its own when the proposal has none' do
    quote.update!(prospect_name: nil)

    expect(described_class.new(quote: quote).perform.account.name).to eq("Conta #{quote.id}")
  end
end
