class CreateSalesDiscounts < ActiveRecord::Migration[7.1]
  # The discounts the sales team had before this table existed, so the plan
  # builder offers the same choices on the day it ships. "Isenção implantação"
  # is left for the team to add from the screen: its product is the one the
  # "Isenção da Implantação" coupon is scoped to in Stripe.
  DEFAULTS = [
    { name: 'Reunião', percent: 10, stripe_product_ids: [], expires_with_reservation: true },
    { name: 'Indicação', percent: 5, stripe_product_ids: [], expires_with_reservation: false },
    { name: 'Isenção config. integração API', percent: 100, stripe_product_ids: ['prod_VEfIAj5QnI3OMV'], expires_with_reservation: false },
    { name: 'Isenção desenv. integração API', percent: 100, stripe_product_ids: ['prod_UFkJIYgoIksh1w'], expires_with_reservation: false }
  ].freeze

  def up
    create_table :sales_discounts do |t|
      t.string :name, null: false
      t.decimal :percent, precision: 5, scale: 2, null: false
      t.string :stripe_product_ids, array: true, null: false, default: []
      t.boolean :expires_with_reservation, null: false, default: false
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    now = Time.current
    rows = DEFAULTS.each_with_index.map { |row, index| row.merge(position: index, created_at: now, updated_at: now) }
    execute_insert(rows)
  end

  def down
    drop_table :sales_discounts
  end

  private

  def execute_insert(rows)
    model = Class.new(ActiveRecord::Base) { self.table_name = 'sales_discounts' }
    model.reset_column_information
    model.insert_all!(rows) # rubocop:disable Rails/SkipsModelValidations
  end
end
