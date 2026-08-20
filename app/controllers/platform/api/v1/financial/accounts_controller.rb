# Billing view of the accounts, for automation: who is charged for tokens and
# which Stripe customer each account is paired with.
#
# Read-only on purpose. Turning billing on or off is a decision the finance team
# takes on Financeiro → Vínculos, where it is recorded next to the rest of the
# billing relationship; an automation flipping it would leave nobody knowing who
# decided what.
class Platform::Api::V1::Financial::AccountsController < PlatformController
  DEFAULT_PER_PAGE = 50
  MAX_PER_PAGE = 200

  # Billing is instance-wide rather than scoped to a permissible account, so
  # holding the platform token is the authorization.
  skip_before_action :set_resource, raise: false
  skip_before_action :validate_platform_app_permissible, raise: false

  def index
    accounts = filtered_accounts.page(page).per(per_page)

    render json: {
      accounts: accounts.map { |account| serialize(account) },
      meta: { current_page: accounts.current_page, total_pages: accounts.total_pages, total_count: accounts.total_count }
    }
  end

  private

  def filtered_accounts
    scope = Account.order(:id)
    scope = scope.where(token_billing_enabled: token_billing_filter) unless token_billing_filter.nil?
    scope = scope.where.not(stripe_customer_id: nil) if ActiveModel::Type::Boolean.new.cast(params[:linked_only])
    scope
  end

  # Absent means "every account"; `false` is a real filter and has to survive
  # the cast, which is why the blank check comes first.
  def token_billing_filter
    return nil if params[:token_billing_enabled].blank?

    ActiveModel::Type::Boolean.new.cast(params[:token_billing_enabled])
  end

  def page
    params[:page].presence || 1
  end

  def per_page
    [params[:per_page].presence&.to_i || DEFAULT_PER_PAGE, MAX_PER_PAGE].min
  end

  def serialize(account)
    {
      id: account.id,
      name: account.name,
      token_billing_enabled: account.token_billing_enabled,
      stripe_customer_id: account.stripe_customer_id,
      # An account with no customer cannot be invoiced at all, which is the
      # other half of "can this account be billed this month".
      billable: account.token_billing_enabled && account.stripe_customer_id.present?
    }
  end
end
