# One pass of a contact through a clinic pipeline. Open while the contact is
# on an `open` stage; moving to Ganho or Perdido closes it (closed_at) and the
# contact can enter again later — a new entry, the old one kept as history.
class PipelineEntry < ApplicationRecord
  belongs_to :account
  belongs_to :pipeline
  belongs_to :contact
  belongs_to :stage, class_name: 'PipelineStage', foreign_key: :pipeline_stage_id, inverse_of: :entries
  belongs_to :added_by, class_name: 'User', optional: true
  belongs_to :origin, polymorphic: true, optional: true
  belongs_to :loss_reason, optional: true
  has_many :events, -> { order(:created_at, :id) }, class_name: 'PipelineEntryEvent', dependent: :delete_all, inverse_of: :entry

  enum source: { manual: 0, automatic: 1 }

  scope :open_entries, -> { where(closed_at: nil) }

  def open?
    closed_at.nil?
  end
end
