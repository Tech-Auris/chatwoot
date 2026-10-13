# A Meta pixel the account sends its conversions to. An account can have
# several (its own and an agency's, one per brand…); a matched conversion
# goes to every pixel in `test_mode` or `active`, each with its own access
# token. `test_mode` adds the pixel's test event code, so events land in
# Events Manager → Test Events until the operator flips it to `active`.
# == Schema Information
#
# Table name: marketing_pixels
#
#  id                       :bigint           not null, primary key
#  access_token             :text
#  name                     :string           not null
#  status                   :integer          default("disabled"), not null
#  test_event_code          :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint           not null
#  marketing_integration_id :bigint           not null
#  pixel_id                 :string           not null
#
# Indexes
#
#  idx_on_marketing_integration_id_pixel_id_59ec8c3570  (marketing_integration_id,pixel_id) UNIQUE
#  index_marketing_pixels_on_account_id                 (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (marketing_integration_id => marketing_integrations.id) ON DELETE => cascade
#
class MarketingPixel < ApplicationRecord
  STATUSES = { disabled: 0, test_mode: 1, active: 2 }.freeze

  encrypts :access_token if Chatwoot.encryption_configured?

  enum status: STATUSES

  belongs_to :account
  belongs_to :marketing_integration
  has_many :conversion_event_dispatches, dependent: :nullify

  before_validation :normalize

  validates :name, presence: { message: ->(*) { I18n.t('errors.marketing_pixel.name_blank') } }
  validates :pixel_id, format: { with: /\A\d+\z/, message: ->(*) { I18n.t('errors.marketing_pixel.invalid_id') } },
                       uniqueness: { scope: :marketing_integration_id, message: ->(*) { I18n.t('errors.marketing_pixel.already_added') } }
  validates :access_token, presence: { message: ->(*) { I18n.t('errors.marketing_pixel.token_blank') } }

  scope :sending, -> { where(status: %i[test_mode active]) }

  def send_as_test?
    test_mode? && test_event_code.present?
  end

  private

  def normalize
    self.name = name.to_s.strip
    self.pixel_id = pixel_id.to_s.strip
    self.test_event_code = test_event_code.to_s.strip.presence
  end
end
