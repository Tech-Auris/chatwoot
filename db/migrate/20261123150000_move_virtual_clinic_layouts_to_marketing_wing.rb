# The Clínica virtual got the sala de marketing and a corridor: saved
# layouts move the gerência to the new wing (see
# VirtualClinic::MarketingWingUpgrade).
class MoveVirtualClinicLayoutsToMarketingWing < ActiveRecord::Migration[7.1]
  def up
    VirtualClinicLayout.find_each do |record|
      record.update_column(:layout, VirtualClinic::MarketingWingUpgrade.call(record.layout)) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def down; end
end
