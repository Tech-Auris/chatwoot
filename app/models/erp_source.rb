# An ERP (or calendar) a clinic schedules in. The ids are the ones of the
# Supabase `integration_type` table, so a new ERP is created here with the id it
# has there: n8n sends that same number to both sides. Retired by turning
# `active` off; one an account still uses can't be deleted.
# == Schema Information
#
# Table name: erp_sources
#
#  id         :bigint           not null, primary key
#  active     :boolean          default(TRUE), not null
#  name       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_erp_sources_on_name  (name) UNIQUE
#
class ErpSource < ApplicationRecord
  has_many :accounts, dependent: :restrict_with_error
  has_many :appointments, dependent: :restrict_with_error

  validates :id, presence: true, uniqueness: true, on: :create
  validates :name, presence: true, uniqueness: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:id) }
end
