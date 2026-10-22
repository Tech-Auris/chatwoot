# What was done with an audience, shown under its "Ações" and kept as the
# audit trail: a download, a campaign sent to it or a freeze into a static one.
class AudienceEvent < ApplicationRecord
  belongs_to :audience
  belongs_to :user, optional: true
  belongs_to :campaign, optional: true

  enum :kind, { download: 0, campaign: 1, snapshot: 2 }, validate: true
end
