# Scopes a canned response to a single inbox. NULL keeps the current
# behaviour — the response is global and shows up everywhere.
class AddInboxToCannedResponses < ActiveRecord::Migration[7.1]
  def change
    add_reference :canned_responses, :inbox, null: true, foreign_key: true, index: true
  end
end
