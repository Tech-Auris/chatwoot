# Turns a paid proposal into an AurisChat account.
#
# Runs from the payment confirmation, which can arrive more than once — Stripe
# retries webhooks — so it is idempotent: a proposal that already has an account
# is returned untouched rather than creating a second one.
class Sales::ConvertQuoteService
  Result = Struct.new(:quote, :account, :created, keyword_init: true)

  def initialize(quote:)
    @quote = quote
  end

  def perform
    return Result.new(quote: quote, account: quote.account, created: false) if quote.account_id.present?

    account = nil
    ActiveRecord::Base.transaction do
      account = build_account
      quote.update!(account: account, status: :converted)
    end

    quote.events.create!(event: 'converted', metadata: { account_id: account.id })
    Result.new(quote: quote, account: account, created: true)
  end

  private

  attr_reader :quote

  # The account is named after the clinic the seller picked in ClickUp, which is
  # what the team recognizes it by — never the payer's personal name.
  def build_account
    _user, account = AccountBuilder.new(
      account_name: quote.prospect_name.presence || "Conta #{quote.id}",
      email: quote.prospect_email,
      # A proposal can reach here without a name — the user record still needs
      # one, and the e-mail is the only other thing we are sure of.
      user_full_name: quote.prospect_name.presence || quote.prospect_email.to_s.split('@').first,
      confirmed: true,
      user: existing_user
    ).perform

    account.update!(stripe_customer_id: quote.stripe_customer_id) if quote.stripe_customer_id.present?
    account
  end

  # Somebody who already has a login — a customer of another clinic, or a second
  # sale to the same person — joins the new account instead of failing on a
  # duplicate e-mail.
  def existing_user
    User.from_email(quote.prospect_email)
  end
end
