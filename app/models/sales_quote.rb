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
#  api_integration_waived   :boolean          default(FALSE), not null
#  asaas_invoice_url        :string
#  asaas_payment_link_url   :string
#  billing_cycle            :integer
#  billing_name             :string
#  clickup_status           :string
#  clickup_status_synced_at :datetime
#  company_document         :string
#  company_name             :string
#  currency                 :string           default("brl"), not null
#  discount_amount          :integer          default(0), not null
#  discount_summary         :string
#  inter_pix_payload        :text
#  inter_txid               :string
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
#  token_card_waived_at     :datetime
#  total_amount             :integer          default(0), not null
#  verification_phone_last4 :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint
#  asaas_customer_id        :string
#  asaas_installment_id     :string
#  asaas_payment_link_id    :string
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
#  index_sales_quotes_on_inter_txid       (inter_txid) UNIQUE WHERE (inter_txid IS NOT NULL)
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

  # `details_confirmed` sits between `reserved` and `signed` in the
  # customer's journey: the prospect has filled name / clinic / contact /
  # document on the public page but has not accepted the terms yet.
  # Its integer value (7) is out of order because the earlier six values
  # are already in production and shifting them would rewrite every row —
  # the enum's declared order carries the lifecycle, the underlying
  # numbers only need to stay unique.
  enum :status, { draft: 0, reserved: 1, details_confirmed: 7, signed: 2, paid: 3, converted: 4, expired: 5, cancelled: 6 }
  # Boleto is a parcelled AsaaS instalment book — one boleto per month, N
  # boletos for a plan of N months (6 for semiannual, 12 for annual). Same
  # shape as the card path (which is the card auth split into N by AsaaS);
  # `billingType` picks between the two on the AsaaS side. Not offered on
  # monthly plans because a monthly PIX/boleto would mean chasing a transfer
  # every month. Boleto sits at list price like the card — the PIX à-vista
  # discount is a courtesy for a customer paying us directly, not for one
  # whose bank compensates the boleto D+1.
  enum :payment_method, { pix: 0, card: 1, boleto: 2 }, prefix: true
  enum :billing_cycle, { monthly: 0, semiannual: 1, annual: 2 }, prefix: true

  validates :public_token, presence: true, uniqueness: true
  validates :access_code, presence: true
  validates :clickup_task_id, presence: true

  # The prospect fills the CPF on the public form and (optionally) a CNPJ if
  # they want the invoice on the company. A malformed value used to travel
  # all the way to Stripe as a `br_cnpj` (or `br_cpf`) and get rejected there,
  # with the sale already closed and the customer already created without
  # the tax id — the operator had to notice and clean up. Validate on
  # change only, so a legacy row with a bad document can still receive
  # unrelated updates while a new save cannot enter an invalid value.
  validate :prospect_document_matches_cpf, if: -> { will_save_change_to_prospect_document? && prospect_document.present? }
  validate :company_document_matches_cnpj, if: -> { will_save_change_to_company_document? && company_document.present? }

  before_validation :assign_credentials, on: :create

  scope :open_deals, -> { where.not(status: [:converted, :expired, :cancelled]) }

  # Signed and not yet an account, minus the monthly card sale — that one is a
  # Stripe subscription, and Stripe confirms it through the webhook.
  scope :awaiting_manual_payment, lambda {
    where(status: :signed, account_id: nil)
      .where.not('payment_method = :card AND billing_cycle = :monthly',
                 card: payment_methods[:card], monthly: billing_cycles[:monthly])
  }

  # The card for the token charges is not always possible: somebody who paid
  # the year by PIX may have none. The sales team says so, and from then on the
  # usage is charged by invoice like everything else they pay outside Stripe.
  def token_card_settled?
    token_payment_method_id.present? || token_card_waived_at.present?
  end

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

  # What the customer actually pays on this proposal — `total_amount` is the
  # cart total (the "list price" of the proposal after the meeting discount
  # and any product coupons). When the customer picks PIX on a semiannual or
  # annual plan, a further percent comes off; the invoice and any future
  # PIX renewal need the discounted number, or we would be billing the "à
  # vista" hint the proposal already showed and charging something else.
  # Card sales get the list price back (no PIX percent applies).
  def effective_charge_amount
    return total_amount unless payment_method_pix?

    percent = Sales::CheckoutService.pix_discount_for(billing_cycle)
    return total_amount if percent.to_i.zero?

    total_amount - ((total_amount * percent) / 100.0).round
  end

  # The PIX percent baked into `effective_charge_amount`, exposed so the
  # invoice description can say what was discounted.
  def pix_discount_percent
    return 0 unless payment_method_pix?

    Sales::CheckoutService.pix_discount_for(billing_cycle).to_i
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

  def prospect_document_matches_cpf
    return if BrDocumentChecksum.valid_cpf?(prospect_document)

    errors.add(:prospect_document, 'CPF inválido')
  end

  def company_document_matches_cnpj
    return if BrDocumentChecksum.valid_cnpj?(company_document)

    errors.add(:company_document, 'CNPJ inválido')
  end
end
