# New accounts should land on the attribute-based AI status by default —
# the label-based mode is the legacy path we only keep for accounts that
# have not been migrated yet. Flipping the column default so any new
# account (via Super Admin, API or factory) starts with the modern mode.
#
# Existing rows are NOT touched — a `change_column_default` only affects
# subsequent inserts. Accounts still on the legacy mode stay put until
# a super admin migrates them explicitly.
class ChangeAiStatusUsesAttributeDefaultToTrue < ActiveRecord::Migration[7.1]
  def up
    change_column_default :accounts, :ai_status_uses_attribute, from: false, to: true
  end

  def down
    change_column_default :accounts, :ai_status_uses_attribute, from: true, to: false
  end
end
