# Settings of each `accounts.status`: the label Super Admin shows and what the
# n8n secretary reads to decide whether to answer (`name`, as in the old
# Supabase `status_secretaria`) and whether to leave the team a private note.
# == Schema Information
#
# Table name: account_statuses
#
#  id                       :bigint           not null, primary key
#  label                    :string           not null
#  message_cooldown_minutes :integer
#  name                     :string           not null
#  private_message          :text
#  send_private_message     :boolean          default(FALSE), not null
#  status                   :integer          not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
# Indexes
#
#  index_account_statuses_on_status  (status) UNIQUE
#
class AccountStatus < ApplicationRecord
  enum status: Account.statuses

  validates :status, presence: true, uniqueness: true
  validates :label, :name, presence: true
  validates :private_message, :message_cooldown_minutes, presence: true, if: :send_private_message?

  scope :ordered, -> { order(:status) }

  def webhook_data
    slice(:name, :send_private_message, :private_message, :message_cooldown_minutes).symbolize_keys
  end
end
