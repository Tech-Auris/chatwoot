# Optional label stamped on every conversation a campaign touches, so the team
# can filter later which conversations came from which campaign.
class AddConversationLabelToCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_column :campaigns, :conversation_label, :string
  end
end
