class AddMoreMenuFlagsToAccounts < ActiveRecord::Migration[7.1]
  # Three more Auris menu-visibility toggles, mirroring the pattern of
  # `inbox_view_menu_enabled` and `help_center_menu_enabled`. All default
  # to false so both new signups AND existing accounts land as hidden;
  # super-admin explicitly opts each account into the menu.
  def change
    add_column :accounts, :campaigns_live_chat_menu_enabled, :boolean, default: false, null: false
    add_column :accounts, :campaigns_sms_menu_enabled, :boolean, default: false, null: false
    add_column :accounts, :settings_macros_menu_enabled, :boolean, default: false, null: false
  end
end
