# == Schema Information
#
# Table name: virtual_clinic_layouts
#
#  id            :bigint           not null, primary key
#  layout        :jsonb            not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  updated_by_id :bigint
#
# Indexes
#
#  index_virtual_clinic_layouts_on_account_id     (account_id) UNIQUE
#  index_virtual_clinic_layouts_on_updated_by_id  (updated_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (updated_by_id => users.id) ON DELETE => nullify
#
class VirtualClinicLayout < ApplicationRecord
  belongs_to :account
  belongs_to :updated_by, class_name: 'User', optional: true

  validates :account_id, uniqueness: true
  validate { VirtualClinic::LayoutValidator.new(layout).errors.each { |message| errors.add(:layout, message) } }

  # The name the clinic gave an AI teammate in the editor, if any.
  def team_name(persona)
    layout.dig('team', persona.to_s, 'name').presence
  end
end
