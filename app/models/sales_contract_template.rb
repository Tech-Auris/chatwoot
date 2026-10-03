# The contract the hiring area generates for semiannual and annual plans, kept
# as versions: saving the template creates a new one, and every contract keeps
# the version it was generated from. The first version comes from
# config/sales/contract_template.html.
# == Schema Information
#
# Table name: sales_contract_templates
#
#  id              :bigint           not null, primary key
#  content         :text             not null
#  created_by_name :string
#  version         :integer          not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  index_sales_contract_templates_on_version  (version) UNIQUE
#
class SalesContractTemplate < ApplicationRecord
  DEFAULT_PATH = Rails.root.join('config/sales/contract_template.html')

  ALLOWED_TAGS = %w[p br strong b em i u s h1 h2 h3 h4 ul ol li table thead tbody tr td th span div a hr].freeze
  ALLOWED_ATTRIBUTES = %w[style colspan rowspan href].freeze

  validates :version, presence: true, uniqueness: true
  validates :content, presence: true

  before_validation :sanitize_content

  scope :latest_first, -> { order(version: :desc) }

  def self.current
    latest_first.first || create!(version: 1, content: File.read(DEFAULT_PATH), created_by_name: 'Modelo inicial')
  end

  def self.publish!(content:, created_by_name:)
    create!(version: current.version + 1, content: content, created_by_name: created_by_name)
  end

  private

  def sanitize_content
    self.content = ActionController::Base.helpers.sanitize(content.to_s, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES)
  end
end
