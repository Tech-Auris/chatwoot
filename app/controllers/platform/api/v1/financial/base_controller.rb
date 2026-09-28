# Billing is instance-wide rather than scoped to a permissible account, so the
# per-resource permissible check doesn't apply. Instead only the platform apps
# listed in FINANCIAL_PLATFORM_APP_IDS may reach it: any other platform token
# would otherwise see every customer's Stripe id and issue real invoices.
class Platform::Api::V1::Financial::BaseController < PlatformController
  skip_before_action :set_resource, raise: false
  skip_before_action :validate_platform_app_permissible, raise: false
  before_action :ensure_financial_platform_app

  private

  def ensure_financial_platform_app
    allowed_ids = ENV.fetch('FINANCIAL_PLATFORM_APP_IDS', '').split(',').map(&:strip)
    return if allowed_ids.include?(@platform_app.id.to_s)

    render json: { error: 'Platform app not allowed to access financial endpoints' }, status: :forbidden
  end
end
