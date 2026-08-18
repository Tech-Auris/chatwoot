# Spacing between messages of a one-off WhatsApp campaign. Without it the
# campaign enqueues every message at once: a thousand contacts means a
# thousand jobs racing each other, ahead of the replies agents are typing,
# and a burst of templates that pressures the number's quality rating.
class AddCadenceSecondsToCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_column :campaigns, :cadence_seconds, :integer, default: 10, null: false
  end
end
