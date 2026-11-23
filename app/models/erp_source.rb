# An ERP (or calendar) a clinic schedules in. The ids are the ones of the
# Supabase `integration_type` table, so a new ERP is created here with the id it
# has there: n8n sends that same number to both sides. Retired by turning
# `active` off; one an account still uses can't be deleted.
#
# `fields` lists what an account's integration with this ERP holds, and builds
# its Super Admin form: each with the `key` n8n reads from `config`, a `label`,
# a `type` (text, number or json) and whether it is a `secret` (masked).
# == Schema Information
#
# Table name: erp_sources
#
#  id         :bigint           not null, primary key
#  active     :boolean          default(TRUE), not null
#  api_url    :string
#  fields     :jsonb            not null
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
  has_many :account_integrations, dependent: :restrict_with_error

  FIELD_TYPES = %w[text number json].freeze

  validates :id, presence: true, uniqueness: true, on: :create
  validates :name, presence: true, uniqueness: true
  validate :fields_are_valid

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:id) }

  # Takes the form rows (a hash by index) or an array; a row without a key is dropped.
  def fields=(rows)
    rows = rows.to_h.values unless rows.is_a?(Array)
    super(rows.filter_map do |row|
      row = row.to_h.stringify_keys
      key = row['key'].to_s.strip
      next if key.empty?

      { 'key' => key, 'label' => row['label'].to_s.strip.presence || key, 'type' => row['type'].presence || 'text',
        'secret' => ActiveModel::Type::Boolean.new.cast(row['secret']) || false }
    end)
  end

  def secret_keys
    fields.select { |field| field['secret'] }.pluck('key')
  end

  private

  def fields_are_valid
    keys = fields.pluck('key')
    errors.add(:fields, "com chave repetida: #{keys.select { |key| keys.count(key) > 1 }.uniq.join(', ')}") if keys.uniq.size < keys.size
    invalid = fields.pluck('type') - FIELD_TYPES
    errors.add(:fields, "com tipo inválido: #{invalid.uniq.join(', ')}") if invalid.any?
  end
end
