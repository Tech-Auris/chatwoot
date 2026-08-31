# The page the prospect opens. There is no login here — the link carries an
# opaque token, and the two halves the seller sends over WhatsApp (a six digit
# code and the last four digits of the prospect's own number) unlock it.
#
# Access is kept in the session rather than in the URL so the unlocked address
# is not something that can be forwarded further.
class Sales::ProposalsController < ActionController::Base
  ATTEMPT_LIMIT = 10
  ATTEMPT_WINDOW = 10.minutes

  layout 'sales_proposal'

  before_action :set_proposal
  before_action :require_unlock, only: [:show, :save_details, :checkout, :pay, :payment_return, :tokens, :save_token_card]

  def show
    @items = @proposal.items
    # The link never changes, so opening it has to land on the step that is
    # still open. Offering the plan again to somebody who already signed is how
    # the same proposal collected two signatures.
    return redirect_to open_step_path if open_step_path.present?

    # The prospect only sees the confirmation once we know who they are: name,
    # phone, e-mail and document are what the contract and the invoice need.
    render :details unless @proposal.details_complete?
  end

  def save_details
    result = Sales::ProspectDetailsService.new(quote: @proposal, attributes: details_params).perform
    @clickup_error = result.clickup_error

    redirect_to sales_proposal_path(@proposal.public_token)
  rescue ActiveRecord::RecordInvalid => e
    @items = @proposal.items
    render :details, status: :unprocessable_entity, locals: { error: e.record.errors.full_messages.to_sentence }
  end

  def unlock
    return render :locked, status: :too_many_requests, locals: { error: 'Muitas tentativas. Tente novamente em alguns minutos.' } if rate_limited?

    register_attempt

    if @proposal.verify_access(code: params[:access_code], phone_last4: params[:phone_last4])
      session[unlocked_key] = true
      @proposal.events.create!(event: 'opened_by_prospect', metadata: { ip: request.remote_ip })
      redirect_to sales_proposal_path(@proposal.public_token)
    else
      render :locked, status: :unauthorized, locals: { error: 'Código ou telefone não conferem.' }
    end
  end

  def checkout
    @items = @proposal.items
    return redirect_to sales_proposal_status_path(@proposal.public_token) if settled?
    return redirect_to sales_proposal_path(@proposal.public_token) unless @proposal.details_complete?

    load_checkout_data
  rescue Sales::TermsFetcherService::Unavailable => e
    @terms_error = e.message
  end

  # Signs the terms and starts the payment. The signature is recorded here
  # because this is the only place that knows the address and the browser the
  # acceptance came from.
  def pay
    # A page left open in another tab must not start a second payment for a
    # proposal that is already settled.
    return redirect_to sales_proposal_status_path(@proposal.public_token) if settled?
    return render_checkout_error('É preciso aceitar os termos de uso') unless params[:accept_terms] == '1'

    # The signature points at the very text the page rendered, not at whatever
    # the site serves now — otherwise the customer could sign a wording that
    # changed between reading and clicking.
    sign_terms!(params[:terms_version_id])
    result = Sales::CheckoutService.new(
      quote: @proposal, payment_method: params[:payment_method], urls: checkout_urls
    ).perform

    return redirect_to result.checkout_url, allow_other_host: true if result.checkout_url.present?

    redirect_to sales_proposal_payment_return_path(@proposal.public_token)
  rescue Sales::TermsFetcherService::Unavailable, Sales::CheckoutService::TermsNotAccepted,
         Sales::CheckoutService::UnsupportedPaymentMethod,
         Integrations::Stripe::Client::Error, Integrations::Asaas::Client::Error => e
    render_checkout_error(e.message)
  end

  def payment_return
    @items = @proposal.items
  end

  # Third step: the card the token usage will be charged against. It may be the
  # one that just paid the subscription or another — Stripe shows the saved card
  # and lets the customer add a different one.
  def tokens
    @same_card_available = @proposal.payment_method_card?
  end

  def save_token_card
    session = Integrations::Stripe::Client.new.create_setup_session(
      customer_id: stripe_customer_id,
      urls: { success: sales_proposal_status_url(@proposal.public_token, host: public_host),
              cancel: sales_proposal_tokens_url(@proposal.public_token, host: public_host) },
      metadata: { sales_quote_id: @proposal.id }
    )

    redirect_to session.url, allow_other_host: true
  rescue Integrations::Stripe::Client::Error => e
    @same_card_available = @proposal.payment_method_card?
    render :tokens, status: :unprocessable_entity, locals: { error: e.message }
  end

  # Where the customer comes back to, and keeps coming back to, until the
  # account is live.
  def status
    @items = @proposal.items
  end

  private

  # Where the proposal is, when that is somewhere other than the plan:
  #
  #   paid or converted -> the tracking page, there is nothing left to do here
  #   signed by PIX     -> the tracking page, which carries the PIX details
  #   signed by card    -> the payment page, so an abandoned checkout can be
  #                        finished without signing the terms a second time
  #
  # Anything else is still being put together and belongs on the plan.
  def open_step_path
    return sales_proposal_status_path(@proposal.public_token) if settled?
    return nil unless @proposal.signed?

    # Only the Stripe checkout can be picked up where it was left; the PIX and
    # the AsaaS link are both waiting on somebody confirming the money.
    if @proposal.payment_method_card? && Sales::CheckoutService.card_provider_for(@proposal.billing_cycle) == :stripe
      sales_proposal_checkout_path(@proposal.public_token)
    else
      sales_proposal_status_path(@proposal.public_token)
    end
  end

  # The money is in, or the account already exists.
  def settled?
    @proposal.paid? || @proposal.converted?
  end

  # The customer exists in Stripe from the card checkout, and for a PIX sale
  # only when the payment is registered — but the card for the token charges is
  # saved before that, and it has to hang off a customer we can bill later.
  def stripe_customer_id
    @proposal.stripe_customer_id.presence || begin
      id = Sales::StripeCustomerService.new(quote: @proposal).ensure!
      @proposal.update!(stripe_customer_id: id)
      id
    end
  end

  # One signature per proposal and per wording. A customer who comes back to
  # pay is signing the same contract they already signed, and the audit is
  # supposed to show a contract signed once — not once per visit.
  def sign_terms!(version_id)
    version = TermsVersion.find_by(id: version_id)
    raise Sales::TermsFetcherService::Unavailable, 'Recarregue a página para ler os termos antes de assinar' if version.blank?

    signed = @proposal.terms_acceptances.status_signed.find_by(terms_version: version)
    return signed if signed.present?

    acceptance = @proposal.terms_acceptances.create!(terms_version: version, status: :pending)
    acceptance.sign!(
      signer: { name: @proposal.prospect_name, email: @proposal.prospect_email, document: @proposal.prospect_document },
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )
  end

  def checkout_urls
    {
      success: sales_proposal_payment_return_url(@proposal.public_token, host: public_host),
      cancel: sales_proposal_checkout_url(@proposal.public_token, host: public_host)
    }
  end

  def public_host
    ENV.fetch('FRONTEND_URL', request.base_url)
  end

  def load_checkout_data
    @pix_available = Sales::CheckoutService.offers?('pix', @proposal.billing_cycle)
    @pix_discount = Sales::CheckoutService.pix_discount_for(@proposal.billing_cycle)
    @max_installments = Sales::CheckoutService.max_installments_for(@proposal.billing_cycle)
    @terms_version = Sales::TermsFetcherService.new.perform
  end

  def render_checkout_error(message)
    @items = @proposal.items
    load_checkout_data
    render :checkout, status: :unprocessable_entity, locals: { error: message }
  rescue Sales::TermsFetcherService::Unavailable => e
    @terms_error = e.message
    render :checkout, status: :unprocessable_entity, locals: { error: message }
  end

  def details_params
    params.require(:proposal).permit(:name, :company_name, :email, :phone, :document, :billing_name, :company_document)
  end

  def set_proposal
    @proposal = SalesQuote.find_by!(public_token: params[:token])
  end

  def require_unlock
    return if session[unlocked_key]

    render :locked, locals: { error: nil }
  end

  def unlocked_key
    "sales_proposal_#{@proposal.id}_unlocked"
  end

  # Six digits and four phone digits are ten million combinations, which is only
  # safe while guessing stays slow. The counter lives in Redis rather than in
  # the Rails cache because that one is a null store in some environments — a
  # rate limit that silently counts nothing is worse than none at all.
  def rate_limited?
    Redis::Alfred.get(attempts_key).to_i >= ATTEMPT_LIMIT
  end

  def register_attempt
    attempts = Redis::Alfred.incr(attempts_key)
    Redis::Alfred.with { |conn| conn.expire(attempts_key, ATTEMPT_WINDOW.to_i) } if attempts == 1
  end

  def attempts_key
    "sales_proposal_attempts/#{@proposal.id}/#{request.remote_ip}"
  end
end
