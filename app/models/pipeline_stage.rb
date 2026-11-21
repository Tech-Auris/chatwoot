# A stage of a clinic pipeline. `open` stages are the clinic's own, always
# ordered before the fixed `won` (Ganho) and `lost` (Perdido), which every
# pipeline has and can be neither renamed nor deleted.
class PipelineStage < ApplicationRecord
  belongs_to :pipeline
  has_many :entries, class_name: 'PipelineEntry', dependent: :restrict_with_error

  enum kind: { open: 0, won: 1, lost: 2 }

  validates :name, presence: true, uniqueness: { scope: :pipeline_id, case_sensitive: false }
  validates :color, presence: true
  validate :closing_stage_unchanged, on: :update

  before_validation :place_before_closing_stages, on: :create, if: :open?

  def closing?
    won? || lost?
  end

  private

  def closing_stage_unchanged
    errors.add(:base, I18n.t('pipelines.errors.closing_stage_locked')) if closing? && name_changed?
  end

  def place_before_closing_stages
    return if position_changed?

    self.position = (pipeline.stages.open.maximum(:position) || -1) + 1
  end
end
