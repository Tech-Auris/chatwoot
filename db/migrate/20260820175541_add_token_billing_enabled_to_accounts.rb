class AddTokenBillingEnabledToAccounts < ActiveRecord::Migration[7.1]
  def change
    # Nullable on purpose: nil means "bills tokens", so every account that
    # exists today keeps being billed and only an explicit opt-out changes it.
    add_column :accounts, :token_billing_enabled, :boolean # rubocop:disable Rails/ThreeStateBooleanColumn
  end
end
