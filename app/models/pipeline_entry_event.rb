# Every stage change of a pipeline entry (including the entry itself, with no
# from_stage). Stores stage ids, not names, so renaming a stage keeps the
# history readable.
class PipelineEntryEvent < ApplicationRecord
  SOURCES = %w[web api automation ai].freeze

  belongs_to :entry, class_name: 'PipelineEntry', foreign_key: :pipeline_entry_id, inverse_of: :events
  belongs_to :pipeline
  belongs_to :from_stage, class_name: 'PipelineStage', optional: true
  belongs_to :to_stage, class_name: 'PipelineStage', optional: true
  belongs_to :user, optional: true
  belongs_to :loss_reason, optional: true

  validates :source, inclusion: { in: SOURCES }
end
