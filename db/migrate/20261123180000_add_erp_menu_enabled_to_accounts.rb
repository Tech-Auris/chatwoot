# Per-account release of the "ERP" menu (ERP → Agenda), with the other
# navigation flags (Auris menus grid). Defaults to false and starts released
# only for account 1; a super admin turns it on for the others.
class AddErpMenuEnabledToAccounts < ActiveRecord::Migration[7.1]
  def up
    add_column :accounts, :erp_menu_enabled, :boolean, default: false, null: false
    execute 'UPDATE accounts SET erp_menu_enabled = TRUE WHERE id = 1'
  end

  def down
    remove_column :accounts, :erp_menu_enabled
  end
end
