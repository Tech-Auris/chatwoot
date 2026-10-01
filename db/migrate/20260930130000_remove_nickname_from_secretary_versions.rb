class RemoveNicknameFromSecretaryVersions < ActiveRecord::Migration[7.1]
  def change
    remove_column :secretary_versions, :nickname, :string
  end
end
