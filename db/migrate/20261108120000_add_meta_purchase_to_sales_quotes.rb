# Feeds the Meta Purchase event a sale sends once paid: the ad click id from
# the ClickUp lead and the browser that clicked "Pagar" on the proposal. Also
# seeds Auris's own pixel id in Settings → Commercial.
class AddMetaPurchaseToSalesQuotes < ActiveRecord::Migration[7.1]
  AURIS_PIXEL_ID = '632639385938559'.freeze

  def up
    change_table :sales_quotes, bulk: true do |t|
      t.string :fbclid
      t.datetime :fbclid_captured_at
      t.string :client_ip
      t.string :client_user_agent
    end

    config = InstallationConfig.find_or_initialize_by(name: 'COMMERCIAL_META_PIXEL_ID')
    return if config.persisted? && config.value.present?

    config.value = AURIS_PIXEL_ID
    config.locked = false
    config.save!
  end

  def down
    change_table :sales_quotes, bulk: true do |t|
      t.remove :fbclid, :fbclid_captured_at, :client_ip, :client_user_agent
    end
  end
end
