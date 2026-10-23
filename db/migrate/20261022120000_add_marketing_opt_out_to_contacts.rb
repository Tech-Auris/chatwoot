class AddMarketingOptOutToContacts < ActiveRecord::Migration[7.1]
  def change
    change_table :contacts, bulk: true do |t|
      t.boolean :marketing_opt_out, default: false, null: false
      t.datetime :marketing_opt_out_at
      t.string :marketing_opt_out_source
    end
    add_index :contacts, [:account_id, :marketing_opt_out]

    add_column :campaigns, :skipped_opt_out_count, :integer, default: 0, null: false
  end
end
