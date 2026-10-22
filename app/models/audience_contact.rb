# A member of a static audience.
class AudienceContact < ApplicationRecord
  belongs_to :audience
  belongs_to :contact

  validates :contact_id, uniqueness: { scope: :audience_id }
end
