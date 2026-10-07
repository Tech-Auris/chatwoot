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

  # Every clinic works in Portuguese, on Brasília time, with the funnel on.
  ACCOUNT_LOCALE = 'pt_BR'.freeze
  REPORTING_TIMEZONE = 'America/Sao_Paulo'.freeze
  AURIS_ADMIN_CONFIG = 'COMMERCIAL_ACCOUNT_ADMIN_USER_ID'.freeze

  # Named after the clinic, which is how the team refers to the customer. The
  # contact's own name is the fallback: the clinic is only known once the
  # prospect fills the public form, and a sale can be converted before that.
  #
  # The customer is the account's manager; Auris's own user (Super Admin →
  # Settings → Commercial) is its administrator. Auris sets the account up,
  # so the sign-up questionnaire (`onboarding_step`) is skipped.
  def build_account
    customer, account = AccountBuilder.new(**builder_attributes).perform
    account.update!(locale: ACCOUNT_LOCALE, reporting_timezone: REPORTING_TIMEZONE, funnel_enabled: true,
                    custom_attributes: account.custom_attributes.except('onboarding_step'))
    account.update!(stripe_customer_id: quote.stripe_customer_id) if quote.stripe_customer_id.present?
    account.account_users.find_by!(user: customer).update!(role: :manager)
    add_auris_admin(account)
    account
  end

  def add_auris_admin(account)
    admin = User.find_by(id: GlobalConfigService.load(AURIS_ADMIN_CONFIG, '1'))
    return if admin.nil?

    account.account_users.find_or_initialize_by(user: admin).update!(role: :administrator)
  end

  def builder_attributes
    {
      account_name: account_name,
      email: quote.prospect_email,
      # A proposal can reach here without a name — the user record still needs
      # one, and the e-mail is the only other thing we are sure of.
      user_full_name: quote.prospect_name.presence || quote.prospect_email.to_s.split('@').first,
      confirmed: true,
      user: existing_user
    }
  end

  def account_name
    quote.company_name.presence || quote.prospect_name.presence || "Conta #{quote.id}"
  end

  # Somebody who already has a login — a customer of another clinic, or a second
  # sale to the same person — joins the new account instead of failing on a
  # duplicate e-mail.
  def existing_user
    User.from_email(quote.prospect_email)
  end
end
