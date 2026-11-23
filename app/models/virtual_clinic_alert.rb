# == Schema Information
#
# Table name: virtual_clinic_alerts
#
#  id              :bigint           not null, primary key
#  acknowledged_at :datetime
#  payload         :jsonb            not null
#  persona         :integer          not null
#  rule            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  user_id         :bigint
#
# Indexes
#
#  idx_on_account_id_rule_created_at_3e13cf67c1  (account_id,rule,created_at)
#  index_virtual_clinic_alerts_on_user_id        (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
class VirtualClinicAlert < ApplicationRecord
  belongs_to :account
  # Set for one person's alert (their summary); nil for the whole team.
  belongs_to :user, optional: true

  enum :persona, { secretary: 0, manager: 1, marketing: 2 }

  validates :rule, presence: true

  scope :open, -> { where(acknowledged_at: nil) }
  scope :seen_by, ->(user) { where(user_id: [nil, user.id]) }

  # The alert in words, in the current locale (the payload has the numbers).
  def message
    I18n.t("virtual_clinic.alerts.#{rule}", **payload.symbolize_keys.except(:patients, :inboxes))
  end

  # `account_id` is required: the dashboard drops cable events of other accounts.
  def push_event_data
    { id: id, persona: persona, rule: rule, payload: payload, message: message, created_at: created_at.to_i, account_id: account_id }
  end
end
