# What the customer confirms on "Confirme os dados para o contrato": who signs
# (company or person), the address and how they will pay. Prefilled from the
# reservation, or from the last contract when the data is being edited.
class Sales::ContractForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  ADDRESS_FIELDS = %i[cep logradouro numero complemento bairro cidade uf].freeze

  attribute :person_type, :string, default: 'pj'
  attribute :razao_social, :string
  attribute :cnpj, :string
  attribute :nome, :string
  attribute :cpf, :string
  attribute :email, :string
  attribute :whatsapp, :string
  ADDRESS_FIELDS.each { |field| attribute field, :string }
  attribute :payment_method, :string

  LABELS = { razao_social: 'Razão social', cnpj: 'CNPJ', nome: 'Nome completo', cpf: 'CPF', email: 'E-mail', whatsapp: 'WhatsApp',
             cep: 'CEP', logradouro: 'Logradouro', numero: 'Número', bairro: 'Bairro', cidade: 'Cidade', uf: 'UF',
             payment_method: 'Forma de pagamento', person_type: 'Tipo de contratação' }.freeze

  # The proposal page only speaks Portuguese, whatever the instance locale.
  # rubocop:disable Rails/I18nLocaleTexts
  validates :person_type, inclusion: { in: %w[pj pf] }
  validates :nome, :cpf, :email, :whatsapp, :cep, :logradouro, :numero, :bairro, :cidade, :uf, :payment_method,
            presence: { message: 'é obrigatório' }
  validates :razao_social, :cnpj, presence: { message: 'é obrigatório' }, if: :pj?
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP, message: 'inválido' }, allow_blank: true
  # rubocop:enable Rails/I18nLocaleTexts
  validate :documents_valid
  validate :address_valid

  attr_accessor :quote

  def self.human_attribute_name(attribute, _options = {})
    LABELS[attribute.to_sym] || attribute.to_s.humanize
  end

  def self.prefill(quote)
    previous = quote.contracts.order(:created_at).last&.data
    return new(previous.slice(*attribute_names).merge(quote: quote)) if previous.present?

    new(quote: quote, person_type: 'pj', razao_social: quote.billing_name, cnpj: quote.company_document, nome: quote.prospect_name,
        cpf: quote.prospect_document, email: quote.prospect_email, whatsapp: quote.prospect_phone)
  end

  def pj?
    person_type == 'pj'
  end

  # Stored on the contract: the confirmed data plus the address in one line.
  def data
    values = attributes.except('payment_method').merge('cpf' => format_document(cpf, 11), 'cnpj' => format_document(cnpj, 14))
    values = values.except('razao_social', 'cnpj') unless pj?
    values.merge('endereco' => full_address)
  end

  def full_address
    street = [logradouro, numero, complemento.presence].compact.join(', ')
    "#{street}, #{bairro}, #{cidade}/#{uf.to_s.upcase}, CEP #{format_cep}"
  end

  private

  def documents_valid
    errors.add(:cpf, 'inválido') if cpf.present? && !BrDocumentChecksum.valid_cpf?(cpf)
    errors.add(:cnpj, 'inválido') if pj? && cnpj.present? && !BrDocumentChecksum.valid_cnpj?(cnpj)
  end

  def address_valid
    errors.add(:cep, 'inválido') if cep.present? && cep.gsub(/\D/, '').length != 8
    errors.add(:uf, 'inválida') if uf.present? && uf.strip.length != 2
  end

  # Documents go into the contract formatted, however they were typed.
  def format_document(value, size)
    digits = value.to_s.gsub(/\D/, '')
    return value if digits.length != size

    pattern = size == 11 ? /(\d{3})(\d{3})(\d{3})(\d{2})/ : /(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})/
    size == 11 ? digits.sub(pattern, '\1.\2.\3-\4') : digits.sub(pattern, '\1.\2.\3/\4-\5')
  end

  def format_cep
    digits = cep.to_s.gsub(/\D/, '')
    "#{digits[0, 5]}-#{digits[5, 3]}"
  end
end
