# A member of a static audience.
# == Schema Information
#
# Table name: audience_contacts
#
#  id          :bigint           not null, primary key
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  audience_id :bigint           not null
#  contact_id  :bigint           not null
#
# Indexes
#
#  index_audience_contacts_on_audience_id_and_contact_id  (audience_id,contact_id) UNIQUE
#  index_audience_contacts_on_contact_id                  (contact_id)
#
class AudienceContact < ApplicationRecord
  belongs_to :audience
  belongs_to :contact

  validates :contact_id, uniqueness: { scope: :audience_id }
end
