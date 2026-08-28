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
  before_action :require_unlock, only: [:show, :save_details]

  def show
    @items = @proposal.items
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

  private

  def details_params
    params.require(:proposal).permit(:name, :email, :phone, :document)
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
