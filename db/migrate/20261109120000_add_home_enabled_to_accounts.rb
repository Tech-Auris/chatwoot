# The Início page (day summary + indicators) is rolled out account by account
# from Super Admin, off until each clinic is switched on.
class AddHomeEnabledToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :home_enabled, :boolean, default: false, null: false
  end
end
