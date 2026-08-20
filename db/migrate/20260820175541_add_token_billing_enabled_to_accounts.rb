class AddTokenBillingEnabledToAccounts < ActiveRecord::Migration[7.1]
  def change
    # Every account is charged for tokens; opting one out is the exception, so
    # the default carries the rule and the column never answers "unknown".
    add_column :accounts, :token_billing_enabled, :boolean, null: false, default: true
  end
end
