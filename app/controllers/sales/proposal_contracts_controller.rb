# The steps semiannual and annual plans take between the plan and the
# payment while the contract step is on: the terms of use on their own page,
# then the contract — the data it is generated from, the payment method, and
# where the signature stands on Autentique.
#
# Inherits the proposal page so the unlock, the layout and the views are the
# same ones.
class Sales::ProposalContractsController < Sales::ProposalsController
  before_action :require_unlock
  before_action :require_contract_flow

  # Step 2: the terms of use on their own, before the contract.
  def terms
    return redirect_to sales_proposal_contract_path(@proposal.public_token) if @proposal.terms_signed?

    load_terms
  end

  def accept_terms
    return render_terms('É preciso aceitar os termos de uso') unless params[:accept_terms] == '1'

    sign_terms!(params[:terms_version_id])
    redirect_to sales_proposal_contract_path(@proposal.public_token)
  rescue Sales::TermsFetcherService::Unavailable => e
    render_terms(e.message)
  end

  # Step 3: the data form until a contract goes out, then where
  # its signature stands. Opening the page asks Autentique again.
  def contract
    return redirect_to sales_proposal_terms_path(@proposal.public_token) unless @proposal.terms_signed?

    return render_contract_form(nil, generating: true) if Sales::GenerateContractService.in_progress?(@proposal)

    @contract = @proposal.current_contract
    Sales::ContractStatusService.new(@contract).refresh! if @contract&.status_awaiting_signature?
    return render_contract_form(contract_failure_message) if @contract.nil? || @contract.status_failed?

    render :contract_status
  end

  def generate_contract
    @form = Sales::ContractForm.new(contract_params)
    @form.quote = @proposal
    return render_contract_form(nil, status: :unprocessable_entity) unless @form.valid?

    Sales::GenerateContractService.new(quote: @proposal, form: @form).perform
    redirect_to sales_proposal_contract_path(@proposal.public_token)
  rescue Sales::GenerateContractService::Error => e
    render_contract_form("Não foi possível gerar o contrato: #{e.message}", status: :unprocessable_entity)
  end

  def verify_contract
    contract = @proposal.current_contract
    Sales::ContractStatusService.new(contract).refresh! if contract
    redirect_to sales_proposal_contract_path(@proposal.public_token)
  end

  def edit_contract
    return redirect_to sales_proposal_contract_path(@proposal.public_token) if @proposal.current_contract&.status_signed?

    render_contract_form(nil)
  end

  private

  def require_contract_flow
    return redirect_to sales_proposal_status_path(@proposal.public_token) if settled?
    return redirect_to sales_proposal_path(@proposal.public_token) unless @proposal.details_complete?

    redirect_to sales_proposal_checkout_path(@proposal.public_token) unless @proposal.contract_required?
  end

  def load_terms
    @items = @proposal.items
    @terms_version = Sales::TermsFetcherService.new.perform
  rescue Sales::TermsFetcherService::Unavailable => e
    @terms_error = e.message
  end

  def render_terms(message)
    load_terms
    render :terms, status: :unprocessable_entity, locals: { error: message }
  end

  def render_contract_form(message, status: :ok, generating: false)
    @form ||= Sales::ContractForm.prefill(@proposal)
    render :contract_form, status: status, locals: { error: message, generating: generating }
  end

  # A contract that could not be generated or that Auris could not sign
  # never reached the customer: they see the form again with what happened.
  def contract_failure_message
    return nil unless @contract&.status_failed?

    'Não conseguimos gerar o seu contrato. Confira os dados e tente novamente — se o problema continuar, fale com o seu consultor.'
  end

  def contract_params
    fields = %i[person_type razao_social cnpj nome cpf email whatsapp payment_method] + Sales::ContractForm::ADDRESS_FIELDS
    params.require(:contract).permit(*fields)
  end
end
