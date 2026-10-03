# Moves the signing deadline of a contract to the proposal's new reservation
# date, on Autentique and on our side. A contract that had expired with the
# old reservation goes back to waiting for the customer.
class Sales::ContractDeadlineJob < ApplicationJob
  queue_as :default

  def perform(contract_id)
    contract = SalesContract.find(contract_id)
    deadline = contract.sales_quote.reserved_until
    return if deadline.blank? || contract.autentique_document_id.blank?

    Integrations::Autentique::Client.new.update_deadline(contract.autentique_document_id, deadline)
    contract.update!(deadline_at: deadline, status: :awaiting_signature)
  end
end
