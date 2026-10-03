# Asks Autentique where the customer's signature stands. Runs when the
# webhook arrives, when the customer opens the Contrato page and when they
# click "Já assinou? Verificar assinatura" — the webhook alone is not trusted
# to have arrived.
class Sales::ContractStatusService
  def initialize(contract, client: Integrations::Autentique::Client.new)
    @contract = contract
    @client = client
  end

  def refresh!
    return contract unless contract.status_awaiting_signature? && contract.autentique_document_id.present?

    apply(customer_signature || {})
    contract
  rescue Integrations::Autentique::Client::Error => e
    Rails.logger.warn("Autentique: could not refresh contract #{contract.id}: #{e.message}")
    contract
  end

  private

  attr_reader :contract, :client

  def customer_signature
    document = client.document(contract.autentique_document_id)
    Array(document&.dig('signatures')).find { |sig| sig['email'].to_s.casecmp?(contract.signer_email.to_s) }
  end

  def apply(signature)
    if signature.dig('signed', 'created_at')
      mark_signed!(signature)
    elsif signature.dig('rejected', 'created_at')
      contract.update!(status: :rejected)
    elsif contract.deadline_at&.past?
      contract.update!(status: :expired)
    end
  end

  def mark_signed!(signature)
    contract.update!(status: :signed, signed_at: Time.zone.parse(signature.dig('signed', 'created_at').to_s) || Time.current)
    contract.sales_quote.events.create!(event: 'contract_signed', metadata: { contract_id: contract.id })
    Sales::ContractClickupCommentJob.perform_later(contract.id, 'signed')
  end
end
