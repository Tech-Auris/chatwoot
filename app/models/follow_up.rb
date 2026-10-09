# == Schema Information
#
# Table name: follow_ups
#
#  id              :bigint           not null, primary key
#  delay_minutes   :integer          not null
#  delivery_status :integer          default("pending"), not null
#  error_message   :text
#  outcome         :integer          default("waiting"), not null
#  outcome_at      :datetime
#  processed_at    :datetime
#  step            :integer          not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  conversation_id :bigint           not null
#  inbox_id        :bigint           not null
#  message_id      :bigint
#  run_id          :string           not null
#
# Indexes
#
#  index_follow_ups_on_account_id_and_created_at            (account_id,created_at)
#  index_follow_ups_on_conversation_id_and_run_id_and_step  (conversation_id,run_id,step) UNIQUE
#  index_follow_ups_on_inbox_id                             (inbox_id)
#
# A follow-up (FUP) sent by the n8n workflow to a patient who stopped
# replying. Two statuses: `delivery_status` is the processing side (did the
# message go out?) and `outcome` is what the clinic cares about (did the
# patient come back?). `delay_minutes` is kept as sent, so later changes to
# the account setup don't rewrite history.
class FollowUp < ApplicationRecord
  MAX_STEP = 5

  belongs_to :account
  belongs_to :conversation
  belongs_to :inbox
  belongs_to :message, optional: true

  enum :delivery_status, { pending: 0, sent: 1, failed: 2 }, prefix: :delivery, validate: true
  enum :outcome, { waiting: 0, reengaged: 1, closed: 2, no_response: 3 }, prefix: true, validate: true

  validates :run_id, presence: true
  validates :step, inclusion: { in: 1..MAX_STEP }, uniqueness: { scope: [:conversation_id, :run_id] }
  validates :delay_minutes, numericality: { only_integer: true, greater_than: 0 }

  before_save :stamp_processed_at, if: -> { delivery_status_changed? && !delivery_pending? }
  before_save :stamp_outcome_at, if: -> { outcome_changed? && !outcome_waiting? }

  private

  def stamp_processed_at
    self.processed_at ||= Time.current
  end

  def stamp_outcome_at
    self.outcome_at = Time.current
  end
end
