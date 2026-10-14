# A company whose LLMs the secretary can run on (OpenAI, Anthropic,
# Inference). Registered in Super Admin; each n8n credential maps to one.
# == Schema Information
#
# Table name: ai_providers
#
#  id         :bigint           not null, primary key
#  key        :string           not null
#  name       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_ai_providers_on_key  (key) UNIQUE
#
class AiProvider < ApplicationRecord
  has_many :ai_models, dependent: :restrict_with_error

  validates :name, presence: true
  validates :key, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }

  scope :ordered, -> { order(:name) }
end
