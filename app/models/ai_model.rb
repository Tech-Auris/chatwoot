# An LLM the secretary can run on. `key` is what the n8n secretary reads to
# pick its model node (the `secretaria:<key>:prompt_v1` tag), so a new model
# also needs its node in n8n. A `retired` model keeps serving the accounts
# already on it but can no longer be picked.
# == Schema Information
#
# Table name: ai_models
#
#  id             :bigint           not null, primary key
#  key            :string           not null
#  name           :string           not null
#  status         :integer          default("active"), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  ai_provider_id :bigint           not null
#  model_id       :string           not null
#
# Indexes
#
#  index_ai_models_on_ai_provider_id  (ai_provider_id)
#  index_ai_models_on_key             (key) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (ai_provider_id => ai_providers.id)
#
class AiModel < ApplicationRecord
  enum status: { active: 0, retired: 1 }

  belongs_to :ai_provider
  has_many :account_secretaries, dependent: :restrict_with_error

  validates :name, :model_id, presence: true
  validates :key, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }

  scope :ordered, -> { order(:name) }

  def webhook_data
    { provider: ai_provider.key, key: key, model: model_id }
  end
end
