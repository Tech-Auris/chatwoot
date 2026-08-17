# Links an AurisChat account to its customer in the Auris Stripe account. The
# id lives in a column of its own instead of `custom_attributes` so the pairing
# can carry a unique index — one account per Stripe customer, one customer per
# account.
#
# No backfill on purpose. `custom_attributes['stripe_customer_id']`, written by
# the Chatwoot Cloud billing services, points at a customer in *Chatwoot's*
# Stripe account, which has nothing to do with who pays Auris. Copying it here
# would produce links to customer ids that don't exist on our side, and they
# would look legitimate on the reconciliation screen. Every pairing starts
# empty and is confirmed by a human.
class AddStripeCustomerIdToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :stripe_customer_id, :string
    add_index :accounts, :stripe_customer_id, unique: true, where: 'stripe_customer_id IS NOT NULL'
  end
end
