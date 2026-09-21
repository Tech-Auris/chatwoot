# Immutable log of every successful password / SSO login. Written by the
# session controller and consumed by the Super Admin audit page — no
# frontend of a customer account ever reads this table.
#
# One row per (login, account) so filtering by account is O(indexed lookup).
# Users with no account at login time (edge case) still get one row with a
# null account_id so nothing is lost.
# == Schema Information
#
# Table name: login_events
#
#  id               :bigint           not null, primary key
#  browser_name     :string
#  browser_version  :string
#  city             :string
#  country          :string
#  country_code     :string
#  device_name      :string
#  ip_address       :string
#  platform_name    :string
#  platform_version :string
#  role             :integer
#  user_agent       :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint
#  user_id          :bigint           not null
#
# Indexes
#
#  index_login_events_on_account_id_and_created_at  (account_id,created_at DESC)
#  index_login_events_on_user_id_and_created_at     (user_id,created_at DESC)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (user_id => users.id)
#
class LoginEvent < ApplicationRecord
  belongs_to :user
  belongs_to :account, optional: true

  # Mirrors AccountUser.role — snapshot at login time so a later demotion
  # does not rewrite history.
  enum role: { agent: 0, administrator: 1, manager: 2 }, _prefix: true

  scope :for_account, ->(account_id) { where(account_id: account_id) if account_id.present? }
  scope :for_role, ->(role) { where(role: role) if role.present? }
  scope :recent_first, -> { order(created_at: :desc) }
end
