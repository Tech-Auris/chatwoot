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
    params[:controller].in? %w[super_admin/reports/health_score super_admin/reports/inbox_status
                               super_admin/terms_acceptances]
  end

  def operations_pages
    terms = { label: 'Terms of use', url: super_admin_terms_acceptances_url }
    # A restricted console reaches the terms audit and nothing else here.
    return [terms] if current_super_admin&.restricted?

    [
      { label: 'Health Score', url: super_admin_reports_health_score_url },
      { label: 'Inbox status', url: super_admin_reports_inbox_status_url },
      terms
    ]
  end

  def commercial_open?
    params[:controller].start_with?('super_admin/commercial/')
  end

  def commercial_pages
    [
      { label: 'Plan builder', url: super_admin_commercial_quotes_url },
      { label: 'Reservations', url: super_admin_commercial_reservations_url }
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
