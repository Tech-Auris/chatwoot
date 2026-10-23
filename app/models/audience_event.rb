# What was done with an audience, shown under its "Ações" and kept as the
# audit trail: a download, a campaign sent to it or a freeze into a static one.
# == Schema Information
#
# Table name: audience_events
#
#  id             :bigint           not null, primary key
#  contacts_count :integer          default(0), not null
#  format         :string
#  kind           :integer          not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  audience_id    :bigint           not null
#  campaign_id    :bigint
#  user_id        :bigint
#
# Indexes
#
#  index_audience_events_on_audience_id  (audience_id)
#
class AudienceEvent < ApplicationRecord
  belongs_to :audience
  belongs_to :user, optional: true
  belongs_to :campaign, optional: true

  enum :kind, { download: 0, campaign: 1, snapshot: 2 }, validate: true
end
