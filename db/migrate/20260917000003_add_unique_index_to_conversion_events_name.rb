class AddUniqueIndexToConversionEventsName < ActiveRecord::Migration[7.1]
  # Enforces the `validates :name, uniqueness: { scope: :account_id }` on the
  # DB side too — without it a race between two admins creating the same
  # event name at the same moment would slip past the AR validation.
  def change
    add_index :conversion_events, %i[account_id name], unique: true
  end
end
