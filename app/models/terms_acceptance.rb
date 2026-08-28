# Who accepted which terms, when, and from where.
#
# Kept apart from the sale on purpose: the same record type also serves a
# re-signature asked of an existing account, with no proposal behind it.
# == Schema Information
#
# Table name: terms_acceptances
#
#  id               :bigint           not null, primary key
#  ip_address       :string
#  request_token    :string
#  requested_at     :datetime
#  signed_at        :datetime
#  signer_document  :string
#  signer_email     :string
#  signer_name      :string
#  status           :integer          default("pending"), not null
#  user_agent       :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint
#  sales_quote_id   :bigint
#  terms_version_id :bigint           not null
#
# Indexes
#
#  index_terms_acceptances_on_account_id        (account_id)
#  index_terms_acceptances_on_request_token     (request_token) UNIQUE
#  index_terms_acceptances_on_sales_quote_id    (sales_quote_id)
#  index_terms_acceptances_on_status            (status)
#  index_terms_acceptances_on_terms_version_id  (terms_version_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (sales_quote_id => sales_quotes.id)
#  fk_rails_...  (terms_version_id => terms_versions.id)
#
class TermsAcceptance < ApplicationRecord
  belongs_to :terms_version
  belongs_to :sales_quote, optional: true
  belongs_to :account, optional: true

  enum :status, { pending: 0, signed: 1, cancelled: 2 }, prefix: true

  validates :signer_name, :signer_email, :signed_at, :ip_address, presence: true, if: :status_signed?

  before_validation :assign_request_token, on: :create

  scope :awaiting_signature, -> { status_pending }

  def sign!(signer:, ip_address:, user_agent:)
    update!(
      status: :signed,
      signer_name: signer[:name],
      signer_email: signer[:email],
      signer_document: signer[:document],
      signed_at: Time.current,
      ip_address: ip_address,
      user_agent: user_agent
    )
  end

  private

  # Only a request sent to an existing account needs a link of its own; a
  # signature taken during a sale rides the proposal's token.
  def assign_request_token
    self.request_token ||= SecureRandom.urlsafe_base64(32) if sales_quote_id.blank?
  end
end
