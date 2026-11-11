# Moves the signing deadline of a contract to the proposal's new reservation
# date, on Autentique and on our side. A contract that had expired with the
# old reservation goes back to waiting for the customer.
#
# A contract generated while the reservation had already lapsed went out at
# full price, without the meeting discount the renewal brings back. Moving its
# deadline would keep that price in the PDF, so it is generated again instead.
class Sales::ContractDeadlineJob < ApplicationJob
  queue_as :default

  def perform(contract_id)
    contract = SalesContract.find(contract_id)
    deadline = contract.sales_quote.reserved_until
    return if deadline.blank? || contract.autentique_document_id.blank?
    return regenerate(contract) if contract.deadline_at.nil?

    Integrations::Autentique::Client.new.update_deadline(contract.autentique_document_id, deadline)
    contract.update!(deadline_at: deadline, status: :awaiting_signature)
  end

  private

  def regenerate(contract)
    form = Sales::ContractForm.new(contract.data.slice(*Sales::ContractForm.attribute_names).merge('payment_method' => contract.payment_method))
    Sales::GenerateContractService.new(quote: contract.sales_quote, form: form, replace: true).perform
  end
end
