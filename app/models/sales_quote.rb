# A proposal built by the sales team for a prospect that is not a customer yet.
#
# It carries its own copy of what was offered — names, amounts and the discount
# breakdown — because the catalogue lives in Stripe and moves: a price archived
# next week must not change what the prospect saw and agreed to.
#
# The deal itself lives in ClickUp. This record mirrors the task id and its
# status so the report can be rendered without calling the API per row.
# == Schema Information
#
# Table name: sales_quotes
#
#  id                       :bigint           not null, primary key
#  access_code              :string           not null
#  billing_cycle            :integer
#  billing_name             :string
#  clickup_status           :string
#  clickup_status_synced_at :datetime
#  company_document         :string
#  company_name             :string
#  currency                 :string           default("brl"), not null
#  discount_amount          :integer          default(0), not null
#  discount_summary         :string
#  meeting_discount         :boolean          default(FALSE), not null
#  payment_method           :integer
#  prospect_document        :string
#  prospect_email           :string
#  prospect_name            :string
#  prospect_phone           :string
#  public_token             :string           not null
#  reserved_until           :datetime
#  status                   :integer          default("draft"), not null
#  subtotal_amount          :integer          default(0), not null
#  total_amount             :integer          default(0), not null
#  verification_phone_last4 :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint
#  clickup_task_id          :string           not null
#  coupon_id                :string
#  seller_id                :bigint           not null
#  stripe_customer_id       :string
#  stripe_invoice_id        :string
#  stripe_subscription_id   :string
#  token_payment_method_id  :string
#
# Indexes
#
#  index_sales_quotes_on_account_id       (account_id)
#  index_sales_quotes_on_clickup_task_id  (clickup_task_id)
#  index_sales_quotes_on_public_token     (public_token) UNIQUE
#  index_sales_quotes_on_seller_id        (seller_id)
#  index_sales_quotes_on_status           (status)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (seller_id => users.id)
#
class SalesQuote < ApplicationRecord
  ACCESS_CODE_LENGTH = 6

  belongs_to :seller, class_name: 'User'
  belongs_to :account, optional: true

  has_many :items, class_name: 'SalesQuoteItem', dependent: :destroy
  has_many :events, class_name: 'SalesQuoteEvent', dependent: :destroy
  has_many :terms_acceptances, dependent: :nullify

  enum :status, { draft: 0, reserved: 1, signed: 2, paid: 3, converted: 4, expired: 5, cancelled: 6 }
  enum :payment_method, { pix: 0, card: 1 }, prefix: true
  enum :billing_cycle, { monthly: 0, semiannual: 1, annual: 2 }, prefix: true

  validates :public_token, presence: true, uniqueness: true
  validates :access_code, presence: true
  validates :clickup_task_id, presence: true

  before_validation :assign_credentials, on: :create

  scope :open_deals, -> { where.not(status: [:converted, :expired, :cancelled]) }

  # Everything the contract and the invoice will need from the prospect. Until
  # it is filled, the public page keeps asking rather than moving on.
  def details_complete?
    [prospect_name, company_name, prospect_email, prospect_phone, prospect_document].all?(&:present?)
  end

  # The reservation discount only holds while the reservation does. Past the
  # date the proposal stays reachable, at full price, until someone renews it.
  def reservation_active?
    reserved_until.present? && reserved_until.future?
  end

  # Both halves are sent by the seller over WhatsApp. The phone digits are what
  # a forwarded link does not carry.
  def verify_access(code:, phone_last4:)
    return false if access_code.blank?

    ActiveSupport::SecurityUtils.secure_compare(access_code.to_s, code.to_s) &&
      (verification_phone_last4.blank? ||
        ActiveSupport::SecurityUtils.secure_compare(verification_phone_last4.to_s, phone_last4.to_s))
  end

  private

  def assign_credentials
    self.public_token ||= SecureRandom.urlsafe_base64(32)
    self.access_code ||= SecureRandom.random_number(10**ACCESS_CODE_LENGTH).to_s.rjust(ACCESS_CODE_LENGTH, '0')
    self.verification_phone_last4 ||= prospect_phone.to_s.gsub(/\D/, '').last(4).presence
  end
end
