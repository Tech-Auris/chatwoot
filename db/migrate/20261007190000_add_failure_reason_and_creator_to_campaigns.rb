class AddFailureReasonAndCreatorToCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_column :campaigns, :failure_reason, :string
    add_column :campaigns, :creator_id, :bigint
  end
end
