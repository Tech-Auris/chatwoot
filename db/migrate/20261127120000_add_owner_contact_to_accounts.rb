# Who answers for the clinic (Grupo A of the Supabase `cliente` migration):
# same names as the `cliente` columns, so n8n overlays them on the legacy row.
# `name_institution` is not migrated: the account name stays as it is.
class AddOwnerContactToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :name_owner, :string
    add_column :accounts, :phone_contact, :string
    add_column :accounts, :email_contact, :string
  end
end
