# A super_admin-driven campaign that asks the managers of every account to
# sign a fresh version of the terms of use.
#
# Kept apart from `TermsAcceptance` so that the campaign has its own lifecycle
# (deadline, expiry, closure) independent of the individual signatures it
# produces — one campaign fans out into many acceptances, one per required
# manager per account, and the report rolls them up back to the campaign.
class TermsAcceptanceRequest < ApplicationRecord
  belongs_to :terms_version
  belongs_to :created_by, class_name: 'SuperAdmin'

  has_many :terms_acceptances, dependent: :restrict_with_error

  DEADLINE_MIN_DAYS = 1
  DEADLINE_MAX_DAYS = 90

  # `signature` is reserved for the sales-checkout flow; the wizard only
  # produces `update` campaigns. The column carries both so a report can
  # answer "signature vs update" without a second join.
  enum :kind, { signature: 0, update: 1 }, prefix: true

  # `open` accepts new signatures; `expired` is set by the deadline job;
  # `closed` is the super_admin's manual wrap-up (Milestone B).
  enum :status, { open: 0, expired: 1, closed: 2 }, prefix: true

  validates :document_date, :deadline_at, presence: true
  validate :deadline_within_bounds

  scope :active, -> { status_open }

  private

  def deadline_within_bounds
    return if deadline_at.blank?

    min = (created_at || Time.current) + DEADLINE_MIN_DAYS.days
    max = (created_at || Time.current) + DEADLINE_MAX_DAYS.days
    return if deadline_at.between?(min, max)

    errors.add(:deadline_at, "must be between #{DEADLINE_MIN_DAYS} and #{DEADLINE_MAX_DAYS} days from now")
  end
end
