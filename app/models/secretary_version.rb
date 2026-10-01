# A release of the AI secretary (n8n router). Registered in Super Admin and
# picked per account; AurisChat posts every `message_created` of the enabled
# inboxes to `webhook_url`, so the customer never sees the webhook itself.
#
# `testing` versions can only run on the Simulador inbox; `retired` ones keep
# serving the accounts still on them but can no longer be picked.
# == Schema Information
#
# Table name: secretary_versions
#
#  id          :bigint           not null, primary key
#  name        :string           not null
#  nickname    :string
#  released_at :datetime
#  status      :integer          default("testing"), not null
#  webhook_url :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  workflow_id :string
#
# Indexes
#
#  index_secretary_versions_on_name         (name) UNIQUE
#  index_secretary_versions_on_webhook_url  (webhook_url) UNIQUE
#
class SecretaryVersion < ApplicationRecord
  enum status: { testing: 0, active: 1, retired: 2 }

  has_many :account_secretaries, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :webhook_url, presence: true, uniqueness: true, format: URI::DEFAULT_PARSER.make_regexp(%w[http https])

  scope :ordered, -> { order(:name) }
end
