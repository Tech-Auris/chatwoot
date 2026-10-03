# The contract a semiannual or annual customer signs before paying: the data
# they confirmed, the payment method they chose, the template version it was
# generated from and where it stands on Autentique. A proposal keeps every
# contract it had; only the newest that is not cancelled counts.
# == Schema Information
#
# Table name: sales_contracts
#
#  id                         :bigint           not null, primary key
#  auris_signed_at            :datetime
#  cancelled_at               :datetime
#  data                       :jsonb            not null
#  deadline_at                :datetime
#  error_message              :text
#  installments               :integer
#  payment_method             :string           not null
#  person_type                :string           not null
#  sandbox                    :boolean          default(FALSE), not null
#  signed_at                  :datetime
#  signing_url                :string
#  status                     :integer          default("failed"), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  autentique_document_id     :string
#  sales_contract_template_id :bigint           not null
#  sales_quote_id             :bigint           not null
#
# Indexes
#
#  index_sales_contracts_on_autentique_document_id      (autentique_document_id) UNIQUE
#  index_sales_contracts_on_sales_contract_template_id  (sales_contract_template_id)
#  index_sales_contracts_on_sales_quote_id              (sales_quote_id)
#
# Foreign Keys
#
#  fk_rails_...  (sales_contract_template_id => sales_contract_templates.id)
#  fk_rails_...  (sales_quote_id => sales_quotes.id) ON DELETE => cascade
#
class SalesContract < ApplicationRecord
  belongs_to :sales_quote
  belongs_to :sales_contract_template

  enum :status, { failed: 0, awaiting_signature: 1, signed: 2, rejected: 3, cancelled: 4, expired: 5 }, prefix: true
  enum :person_type, { pj: 'pj', pf: 'pf' }, prefix: true

  validates :payment_method, inclusion: { in: %w[pix card boleto] }

  scope :live, -> { where.not(status: :cancelled) }

  def template_version
    sales_contract_template.version
  end

  # Who signs for the customer: the legal representative (PJ) or the person
  # themself (PF). The contract goes to this e-mail.
  def signer_email
    data['email']
  end

  def contractor_label
    person_type_pj? ? "#{data['razao_social']} · CNPJ #{data['cnpj']}" : "#{data['nome']} · CPF #{data['cpf']}"
  end
end
