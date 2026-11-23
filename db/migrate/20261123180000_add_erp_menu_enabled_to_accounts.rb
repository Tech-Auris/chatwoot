# Per-account release of the "ERP" menu (ERP → Agenda), with the other
# navigation flags (Auris menus grid). Defaults to false: a super admin turns it
# on account by account, starting with account 1.
class AddErpMenuEnabledToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :erp_menu_enabled, :boolean, default: false, null: false
  end
end
