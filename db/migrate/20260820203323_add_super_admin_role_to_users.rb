class AddSuperAdminRoleToUsers < ActiveRecord::Migration[7.1]
  def change
    # Only meaningful for SuperAdmin records. Nullable and defaulted to the full
    # console so every existing super admin keeps exactly the access they have.
    add_column :users, :super_admin_role, :string
  end
end
