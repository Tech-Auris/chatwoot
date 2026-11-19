# Per-account release of the "Clínica virtual" page. Kept with the other
# navigation/access flags (Auris menus grid), out of `auris_settings` and
# webhook payloads. Defaults to false: a super admin turns it on account by
# account, starting with account 1.
class AddVirtualClinicEnabledToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :virtual_clinic_enabled, :boolean, default: false, null: false
  end
end
