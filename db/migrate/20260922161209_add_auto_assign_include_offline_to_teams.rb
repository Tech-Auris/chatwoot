class AddAutoAssignIncludeOfflineToTeams < ActiveRecord::Migration[7.1]
  # A per-team knob that widens auto-assignment to offline members too.
  # Kept `false` by default so every existing team behaves exactly like
  # before: online-only. The setting only matters when
  # `allow_auto_assign` is `true`.
  def change
    add_column :teams, :auto_assign_include_offline, :boolean, default: false, null: false
  end
end
