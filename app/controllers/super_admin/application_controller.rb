# All Administrate controllers inherit from this
# `Administrate::ApplicationController`, making it the ideal place to put
# authentication logic or other before_actions.
#
# If you want to add pagination or other controller-level concerns,
# you're free to overwrite the RESTful controller actions.
class SuperAdmin::ApplicationController < Administrate::ApplicationController
  include ActionView::Helpers::TagHelper
  include ActionView::Context
  include SuperAdmin::NavigationHelper

  helper_method :render_vue_component, :settings_open?, :settings_pages, :reports_open?, :reports_pages,
                :financial_open?, :financial_pages,
                :commercial_open?, :commercial_pages,
                :operations_open?, :operations_pages
  # authenticiation done via devise : SuperAdmin Model
  before_action :authenticate_super_admin!
  before_action :authorize_console_section!

  # Controllers a finance-only super admin may reach. Everything under
  # Financeiro, plus what any signed-in admin needs to manage their own session:
  # profile, MFA and logout. Anything not listed is refused — a new console
  # section is out of reach until somebody decides otherwise, which is the safe
  # direction for a permission list to fail in.
  # Controllers a sales-only super admin may reach. Same allowlist shape as the
  # finance role: a console section added later is out of reach until somebody
  # decides otherwise.
  COMMERCIAL_ALLOWED_CONTROLLERS = %w[
    super_admin/commercial/quotes
    super_admin/commercial/reservations
    super_admin/terms_acceptances
    super_admin/profile/mfa
    super_admin/sessions/mfa_challenge
    super_admin/devise/sessions
  ].freeze

  FINANCIAL_ALLOWED_CONTROLLERS = %w[
    super_admin/financial/products
    super_admin/financial/customer_links
    super_admin/financial/subscriptions
    super_admin/financial/invoices
    super_admin/financial/token_billings
    super_admin/financial/coupons
    super_admin/financial/pix_renewals
    super_admin/terms_acceptances
    super_admin/profile/mfa
    super_admin/sessions/mfa_challenge
    super_admin/devise/sessions
  ].freeze

  # Override this value to specify the number of elements to display at a time
  # on index pages. Defaults to 20.
  # def records_per_page
  #   params[:per_page] || 20
  # end

  def order
    @order ||= Administrate::Order.new(
      params.fetch(resource_name, {}).fetch(:order, 'id'),
      params.fetch(resource_name, {}).fetch(:direction, 'desc')
    )
  end

  private

  def authorize_console_section!
    return unless current_super_admin&.restricted?
    return if allowed_controllers.include?(params[:controller])

    # rubocop:disable Rails/I18nLocaleTexts
    if current_super_admin.commercial_only?
      redirect_to super_admin_root_path, alert: 'Seu acesso é restrito à seção Comercial.'
    else
      redirect_to super_admin_financial_invoices_path, alert: 'Seu acesso é restrito à seção Financeiro.'
    end
    # rubocop:enable Rails/I18nLocaleTexts
  end

  def allowed_controllers
    return COMMERCIAL_ALLOWED_CONTROLLERS if current_super_admin.commercial_only?

    FINANCIAL_ALLOWED_CONTROLLERS
  end

  def render_vue_component(component_name, props = {})
    html_options = {
      id: 'app',
      data: {
        component_name: component_name,
        props: props.to_json
      }
    }
    content_tag(:div, '', html_options)
  end

  def invalid_action_perfomed
    # rubocop:disable Rails/I18nLocaleTexts
    flash[:error] = 'Invalid action performed'
    # rubocop:enable Rails/I18nLocaleTexts
    redirect_back(fallback_location: root_path)
  end
end
