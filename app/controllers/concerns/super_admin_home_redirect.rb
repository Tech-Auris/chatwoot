# Where to land a super admin right after sign-in. The full console lands on
# the users list (Administrate's default entry point); each restricted role
# lands on the first page of its section, which avoids a bounce through the
# console guard (and the yellow "acesso restrito" flash that comes with it).
module SuperAdminHomeRedirect
  extend ActiveSupport::Concern

  private

  def super_admin_home_path_for(super_admin)
    return super_admin_commercial_quotes_path if super_admin&.commercial_only?
    return super_admin_financial_products_path if super_admin&.financial_only?

    super_admin_users_path
  end
end
