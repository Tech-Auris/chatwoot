# "Gerar contrato": fills the current template with the data the customer
# confirmed, turns it into a PDF and creates it on Autentique. With the
# automatic signature on, Auris's legal representative (the token's user)
# signs first, and only then Autentique invites the customer — the signers go
# in order, so a contract Auris failed to sign never reaches the customer.
class Sales::GenerateContractService
  class Error < StandardError; end

  def initialize(quote:, form:, client: Integrations::Autentique::Client.new)
    @quote = quote
    @form = form
    @client = client
  end

  def perform
    ensure_payment_method!
    cancel_current!
    contract = create_contract
    send_to_autentique(contract)
    contract
  end

  private

  attr_reader :quote, :form, :client

  def ensure_payment_method!
    method = form.payment_method.to_s
    offered = Sales::CheckoutService.offers?(method, quote.billing_cycle) && (method != 'boleto' || quote.boleto_available?)
    raise Error, 'Forma de pagamento não disponível para esta proposta' unless offered
  end

  # Editing the data replaces the contract: the old document is taken down on
  # Autentique before a new one goes out. A signed contract is never replaced.
  def cancel_current!
    current = quote.current_contract
    return if current.nil?
    raise Error, 'O contrato já foi assinado' if current.status_signed?

    delete_document(current.autentique_document_id)
    current.update!(status: :cancelled, cancelled_at: Time.current)
  end

  def create_contract
    quote.contracts.create!(
      sales_contract_template: SalesContractTemplate.current, status: :failed, person_type: form.person_type, data: form.data,
      payment_method: form.payment_method, installments: installments, sandbox: sandbox?,
      deadline_at: (quote.reserved_until if quote.reservation_active?)
    )
  end

  def send_to_autentique(contract)
    document = client.create_document(name: document_name, io: StringIO.new(pdf_for(contract)), filename: "contrato-auris-#{quote.id}.pdf",
                                      signers: signers(contract), deadline_at: contract.deadline_at, sandbox: contract.sandbox)
    contract.update!(autentique_document_id: document['id'], signing_url: signing_url(document, contract))
    sign_for_auris!(contract) if Sales::ContractSettings.auto_sign?
    contract.update!(status: :awaiting_signature, error_message: nil)
    record_sent(contract)
  rescue Integrations::Autentique::Client::Error => e
    contract.update!(status: :failed, error_message: e.message)
    raise Error, e.message
  end

  def record_sent(contract)
    quote.events.create!(event: 'contract_generated', metadata: { contract_id: contract.id, template_version: contract.template_version })
    Sales::ContractClickupCommentJob.perform_later(contract.id, 'generated')
  end

  def sign_for_auris!(contract)
    client.sign_document(contract.autentique_document_id)
    contract.update!(auris_signed_at: Time.current)
  rescue Integrations::Autentique::Client::Error => e
    raise Integrations::Autentique::Client::Error, "Erro na assinatura da Auris: #{e.message}"
  end

  def pdf_for(contract)
    variables = Sales::ContractVariables.for(quote: quote, data: contract.data, payment_method: contract.payment_method)
    html = Sales::ContractTemplateRenderer.new(content: contract.sales_contract_template.content, variables: variables,
                                               person_type: contract.person_type).render
    Sales::ContractPdfService.new(html).to_pdf
  end

  def signers(contract)
    customer = { email: contract.signer_email, action: 'SIGN' }
    return [customer] unless Sales::ContractSettings.auto_sign?

    [{ email: auris_email, action: 'SIGN' }, customer]
  end

  def auris_email
    @auris_email ||= client.me['email']
  end

  def signing_url(document, contract)
    signature = Array(document['signatures']).find { |sig| sig['email'].to_s.casecmp?(contract.signer_email.to_s) }
    signature&.dig('link', 'short_link')
  end

  def document_name
    "Contrato Auris – #{form.pj? ? form.razao_social : form.nome}"
  end

  def installments
    form.payment_method == 'pix' ? 1 : Sales::CheckoutService.installments_for(quote.billing_cycle)
  end

  def sandbox?
    ActiveModel::Type::Boolean.new.cast(GlobalConfigService.load('AUTENTIQUE_SANDBOX', 'true').to_s)
  end

  def delete_document(document_id)
    client.delete_document(document_id) if document_id.present?
  rescue Integrations::Autentique::Client::Error => e
    Rails.logger.warn("Autentique: could not delete document #{document_id}: #{e.message}")
  end
end
