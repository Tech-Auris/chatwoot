# A clinic pipeline (funil da clínica): stages the clinic defines, plus the
# fixed Ganho / Perdido at the end, and the contacts that pass through it.
class Pipeline < ApplicationRecord
  DEFAULT_COLOR = '#6b7280'.freeze
  WON_COLOR = '#086944'.freeze
  LOST_COLOR = '#dc2626'.freeze

  belongs_to :account
  # Entries go before the stages: a stage holding entries refuses to go.
  has_many :entry_events, class_name: 'PipelineEntryEvent', dependent: :delete_all
  has_many :entries, class_name: 'PipelineEntry', dependent: :delete_all
  has_many :stages, -> { order(:position, :id) }, class_name: 'PipelineStage', dependent: :destroy, inverse_of: :pipeline

  validates :name, presence: true, uniqueness: { scope: :account_id, case_sensitive: false }

  scope :active, -> { where(archived_at: nil) }
  scope :ordered, -> { order(:position, :id) }

  after_create :create_closing_stages!

  def archived?
    archived_at.present?
  end

  def first_open_stage
    stages.find(&:open?)
  end

  private

  def create_closing_stages!
    locale = account.locale.presence || I18n.default_locale
    stages.create!(name: I18n.t('pipelines.stages.won', locale: locale), kind: :won, color: WON_COLOR, position: 1000)
    stages.create!(name: I18n.t('pipelines.stages.lost', locale: locale), kind: :lost, color: LOST_COLOR, position: 1001)
  end
end
