class AddAudienceSourceToCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_reference :campaigns, :audience_source, index: true
  end
end
