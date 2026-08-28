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
    params[:controller].in? %w[super_admin/reports/inbox_status super_admin/reports/health_score
                               super_admin/instance_statuses]
  end

  def reports_pages
    [
      { label: 'Health Score', url: super_admin_reports_health_score_url },
      { label: 'Inbox status', url: super_admin_reports_inbox_status_url },
      { label: 'Instance Health', url: super_admin_instance_status_url }
    ]
  end

  def commercial_open?
    params[:controller].start_with?('super_admin/commercial/')
  end

  def commercial_pages
    [
      { label: 'Montar plano', url: super_admin_commercial_quotes_url }
    ]
  end

  def financial_open?
    params[:controller].start_with?('super_admin/financial/')
  end

  def financial_pages
    [
      { label: 'Produtos', url: super_admin_financial_products_url },
      { label: 'Vínculos', url: super_admin_financial_customer_links_url },
      { label: 'Assinaturas', url: super_admin_financial_subscriptions_url },
      { label: 'Faturas', url: super_admin_financial_invoices_url },
      { label: 'Cupons', url: super_admin_financial_coupons_url },
      { label: 'Cobrança de tokens', url: super_admin_financial_token_billings_url }
    ]
  end
end
