module SuperAdmin::NavigationHelper
  def settings_open?
    params[:controller].in? %w[super_admin/settings super_admin/app_configs]
  end

  def settings_pages
    features = SuperAdmin::FeaturesHelper.available_features.select do |_feature, attrs|
      attrs['config_key'].present? && attrs['enabled']
    end

    # Add general at the beginning
    general_feature = [['general', { 'config_key' => 'general', 'name' => 'General' }]]

    general_feature + features.to_a
  end

  # What drives the AI secretary: its flow versions and the LLMs it can run on.
  def ai_open?
    params[:controller].in? %w[super_admin/secretary_versions super_admin/ai_providers super_admin/ai_models]
  end

  def ai_pages
    [
      { label: 'Secretary Versions', url: super_admin_secretary_versions_url },
      { label: 'Providers', url: super_admin_ai_providers_url },
      { label: 'LLMs', url: super_admin_ai_models_url }
    ]
  end

  def reports_open?
    params[:controller] == 'super_admin/instance_statuses'
  end

  def reports_pages
    [
      { label: 'Instance Health', url: super_admin_instance_status_url }
    ]
  end

  # How the operation is doing and what it has on record — neither a sales nor a
  # finance matter, which is why they sit on their own.
  def operations_open?
    params[:controller].in? %w[super_admin/reports/health_score super_admin/reports/inbox_status super_admin/reports/follow_up_audit
                               super_admin/terms_acceptances super_admin/terms_acceptance_requests
                               super_admin/login_events]
  end

  def operations_pages
    terms = { label: 'Terms of use', url: super_admin_terms_acceptances_url }
    terms_campaigns = { label: 'Terms campaigns', url: super_admin_terms_acceptance_requests_url }
    # A restricted console reaches the terms audit and nothing else here.
    return [terms] if current_super_admin&.restricted?

    [
      { label: 'Health Score', url: super_admin_reports_health_score_url },
      { label: 'Inbox status', url: super_admin_reports_inbox_status_url },
      { label: 'Auditoria de FUP', url: super_admin_reports_follow_up_audit_url },
      terms,
      terms_campaigns,
      { label: 'Login events', url: super_admin_login_events_url }
    ]
  end

  def commercial_open?
    params[:controller].start_with?('super_admin/commercial/')
  end

  def commercial_pages
    [
      { label: 'Plan builder', url: super_admin_commercial_quotes_url },
      { label: 'Reservations', url: super_admin_commercial_reservations_url },
      { label: 'Contrato', url: super_admin_commercial_contract_url }
    ]
  end

  def financial_open?
    params[:controller].start_with?('super_admin/financial/')
  end

  def financial_pages
    [
      { label: 'Products', url: super_admin_financial_products_url },
      { label: 'Customer links', url: super_admin_financial_customer_links_url },
      { label: 'Subscriptions', url: super_admin_financial_subscriptions_url },
      { label: 'Invoices', url: super_admin_financial_invoices_url },
      { label: 'PIX renewals', url: super_admin_financial_pix_renewals_url },
      { label: 'Coupons', url: super_admin_financial_coupons_url },
      { label: 'Token billing', url: super_admin_financial_token_billings_url }
    ]
  end
end
