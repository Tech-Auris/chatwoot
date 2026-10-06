require 'rails_helper'

RSpec.describe Sales::ConvertQuoteService do
  let(:quote) do
    create(:sales_quote, prospect_name: 'Felicia Macedo', company_name: 'Clínica Cinco',
                         prospect_email: 'contato@clinicacinco.com.br', stripe_customer_id: 'cus_1', status: :paid)
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

  it 'sets the account up in Portuguese, on Brasília time, without the sign-up questionnaire' do
    account = described_class.new(quote: quote).perform.account.reload

    expect(account.locale).to eq('pt_BR')
    expect(account.reporting_timezone).to eq('America/Sao_Paulo')
    expect(account.custom_attributes).not_to have_key('onboarding_step')
  end

  it 'makes the customer a manager and the Auris user the administrator' do
    tech = create(:user)
    InstallationConfig.where(name: 'COMMERCIAL_ACCOUNT_ADMIN_USER_ID').first_or_create!(value: tech.id.to_s, locked: false)
                      .update!(value: tech.id.to_s)
    GlobalConfig.clear_cache

    account = described_class.new(quote: quote).perform.account

    roles = account.account_users.includes(:user).to_h { |account_user| [account_user.user.email, account_user.role] }
    expect(roles).to eq('contato@clinicacinco.com.br' => 'manager', tech.email => 'administrator')
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

  # The clinic is what the team calls the customer; the contact's own name is
  # only the fallback, for a sale converted before the form was filled.
  it 'falls back to the contact name when no clinic is known yet' do
    quote.update!(company_name: nil)

    expect(described_class.new(quote: quote).perform.account.name).to eq('Felicia Macedo')
  end

  it 'falls back to a name of its own when the proposal has neither' do
    quote.update!(company_name: nil, prospect_name: nil)

    expect(described_class.new(quote: quote).perform.account.name).to eq("Conta #{quote.id}")
  end
end
