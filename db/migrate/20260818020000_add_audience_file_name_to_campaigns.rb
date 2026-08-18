# Name of the CSV an operator uploaded as the campaign audience. The file
# itself isn't kept — it is turned into contacts at upload time — but the name
# is what lets the campaign card say where the audience came from.
class AddAudienceFileNameToCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_column :campaigns, :audience_file_name, :string
  end
end
