# Reconciliation screen between AurisChat accounts and Stripe customers.
#
# Two views over the same data: "pendentes" (accounts with no Stripe customer
# yet, each with suggested matches) and "conciliados" (already linked, so the
# pairing can be corrected or dropped). Accounts are paginated on our side;
# the Stripe customer list is fetched once per request and reused for both the
# suggestions and the linked-customer details.
class SuperAdmin::Financial::CustomerLinksController < SuperAdmin::ApplicationController
  PER_PAGE = 25

  rescue_from Integrations::Stripe::Client::Unauthorized do |e|
    render json: { error: "Credencial do Stripe inválida: #{e.message}" }, status: :unauthorized
  end

  rescue_from Integrations::Stripe::Client::InvalidRequest do |e|
    render json: { error: e.message }, status: :unprocessable_entity
  end

  rescue_from Integrations::Stripe::Client::ProviderUnavailable do |e|
    render json: { error: "Stripe indisponível: #{e.message}" }, status: :bad_gateway
  end

  # The unique index is the real guard for the one-to-one pairing. It only
  # trips on a race (two operators linking the same customer at once) since the
  # picker already hides taken customers, so answer with something readable
  # instead of a 500.
  rescue_from ActiveRecord::RecordNotUnique do
    render json: { error: 'Esse cliente do Stripe já está vinculado a outra conta.' }, status: :unprocessable_entity
  end

  # Token billing is a decision of ours, not of Stripe — it stays reachable even
  # when the credential is missing or broken.
  before_action :ensure_configured, except: [:index, :token_billing]
  before_action :set_account, only: [:update, :destroy, :customer, :token_billing]

  def index; end

  def data
    render json: {
      accounts: serialize_accounts(paginated_accounts),
      meta: pagination_meta(paginated_accounts),
      customers: available_customers.map { |customer| serialize_customer(customer) }
    }
  end

  # Links an existing Stripe customer to the account, stamping the reverse
  # pointer on Stripe so the pairing is visible from both sides.
  def update
    customer_id = params.require(:stripe_customer_id)

    @account.update!(stripe_customer_id: customer_id)
    client.link_customer_to_account(customer_id, @account.id)

    render json: { account: link_summary(@account) }
  end

  def destroy
    previous_customer_id = @account.stripe_customer_id
    @account.update!(stripe_customer_id: nil)
    client.unlink_customer(previous_customer_id) if previous_customer_id.present?

    render json: { account: link_summary(@account) }
  end

  # Turns token billing on or off for the account. Not every customer is charged
  # for usage — internal accounts, courtesy, contracts where it is bundled — and
  # the monthly batch has to leave those out on its own.
  def token_billing
    @account.update!(token_billing_enabled: ActiveModel::Type::Boolean.new.cast(params.require(:enabled)))

    render json: { account: link_summary(@account) }
  end

  # Creates the Stripe customer for an account that does not exist there yet
  # and links it in the same step.
  def customer
    customer = client.create_customer(
      name: @account.name,
      email: @account.administrators.first&.email,
      account_id: @account.id
    )
    @account.update!(stripe_customer_id: customer.id)

    render json: { account: link_summary(@account) }, status: :created
  end

  private

  def client
    @client ||= Integrations::Stripe::Client.new
  end

  def ensure_configured
    return if client.configured?

    render json: { error: 'Stripe não está configurado. Salve a Stripe Secret Key em Settings → Stripe.' },
           status: :unprocessable_entity
  end

  def set_account
    @account = Account.find(params[:account_id])
  end

  def linked_scope?
    params[:scope] == 'linked'
  end

  def paginated_accounts
    @paginated_accounts ||= begin
      scope = Account.order(:name)
      scope = linked_scope? ? scope.where.not(stripe_customer_id: nil) : scope.where(stripe_customer_id: nil)
      scope = scope.where('accounts.name ILIKE ?', "%#{params[:search]}%") if params[:search].present?
      scope.page(params[:page] || 1).per(PER_PAGE)
    end
  end

  def stripe_customers
    @stripe_customers ||= client.list_customers
  end

  def customers_by_id
    @customers_by_id ||= stripe_customers.index_by(&:id)
  end

  # Customers already claimed by another account are dropped from the picker so
  # the 1-to-1 pairing can't be broken from the UI. Stripe returns them newest
  # first; the picker is a long list someone reads, so it is sorted by name.
  def available_customers
    linked_ids = Account.where.not(stripe_customer_id: nil).pluck(:stripe_customer_id)
    linked_ids -= paginated_accounts.filter_map(&:stripe_customer_id)

    stripe_customers.reject { |customer| linked_ids.include?(customer.id) }
                    .sort_by { |customer| sort_key(customer) }
  end

  # Accents and casing shouldn't scatter the list ("Ângela" belongs next to
  # "Ana"), and unnamed customers fall back to whatever identifies them.
  def sort_key(customer)
    label = customer.name.presence || customer.email.presence || customer.id
    I18n.transliterate(label.to_s).downcase
  end

  # One query for every administrator of the accounts on the page, so building
  # suggestions doesn't hit the database per row.
  def admin_emails_by_account
    @admin_emails_by_account ||= AccountUser.where(account_id: paginated_accounts.map(&:id), role: :administrator)
                                            .includes(:user)
                                            .group_by(&:account_id)
                                            .transform_values { |account_users| account_users.map { |au| au.user.email } }
  end

  def matcher
    @matcher ||= Financial::StripeCustomerMatcher.new(available_customers)
  end

  # Member actions answer with just the pairing — the screen refetches the list
  # afterwards, so rebuilding suggestions and the customer index here would be
  # two Stripe round trips for data nobody reads.
  def link_summary(account)
    { id: account.id, name: account.name, stripe_customer_id: account.stripe_customer_id,
      token_billing_enabled: account.token_billing_enabled? }
  end

  def serialize_accounts(accounts)
    accounts.map { |account| serialize_account(account, customers_by_id) }
  end

  def serialize_account(account, customers)
    {
      id: account.id,
      name: account.name,
      # Whether this account is charged for token usage. Lives here because
      # this is the screen that owns the billing relationship of an account.
      token_billing_enabled: account.token_billing_enabled?,
      admin_emails: admin_emails_by_account[account.id] || [],
      stripe_customer_id: account.stripe_customer_id,
      stripe_customer: serialize_customer(customers[account.stripe_customer_id]),
      suggestions: account.stripe_customer_id.present? ? [] : matcher.suggestions_for(account, admin_emails_by_account[account.id])
    }
  end

  def serialize_customer(customer)
    return nil if customer.blank?

    { id: customer.id, name: customer.name, email: customer.email }
  end

  def pagination_meta(accounts)
    {
      current_page: accounts.current_page,
      total_pages: accounts.total_pages,
      total_count: accounts.total_count,
      linked_count: Account.where.not(stripe_customer_id: nil).count,
      pending_count: Account.where(stripe_customer_id: nil).count
    }
  end
end
