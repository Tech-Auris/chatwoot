# Keeps the payment page of a semiannual/annual proposal shut until its
# contract is signed (contract step on), and points to the step still open.
module Sales::ProposalContractGate
  extend ActiveSupport::Concern

  private

  # Semiannual/annual with the contract step: the payment page only opens once
  # the contract is signed, and a direct link goes back to the step still open.
  def contract_pending?
    @proposal.contract_required? && signed_contract.nil?
  end

  def signed_contract
    return @signed_contract if defined?(@signed_contract)

    contract = @proposal.current_contract if @proposal.contract_required?
    @signed_contract = contract&.status_signed? ? contract : nil
  end

  # A page left open in another tab must not start a second payment for a
  # proposal that is already settled, nor one whose contract is not signed.
  def pay_blocked_path
    return sales_proposal_status_path(@proposal.public_token) if settled?

    contract_step_path if contract_pending?
  end

  # A signed contract fixes how the customer pays.
  def chosen_payment_method
    signed_contract&.payment_method || params[:payment_method]
  end

  def contract_step_path
    return sales_proposal_terms_path(@proposal.public_token) unless @proposal.terms_signed?

    sales_proposal_contract_path(@proposal.public_token)
  end
end
