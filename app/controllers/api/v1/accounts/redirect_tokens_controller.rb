class Api::V1::Accounts::RedirectTokensController < Api::V1::Accounts::BaseController
  def create
    inbox = Current.account.inboxes.find(permitted_params[:inbox_id])
    authorize inbox, :show?
    return render(json: { error: 'not_a_web_widget' }, status: :unprocessable_entity) unless inbox.web_widget?
    return render(json: { error: 'contact_not_found' }, status: :unprocessable_entity) if contact_filters.present? && redirect_contact.blank?

    payload = { inbox_id: inbox.id, contact_id: redirect_contact&.id, message: permitted_params[:message] }.compact
    token = ::Widget::RedirectToken.generate(payload, ttl: ttl)

    render json: { token: token, expires_in: ttl, website_url: inbox.channel.website_url }
  end

  private

  def ttl
    (permitted_params[:ttl_seconds].presence&.to_i || ::Widget::RedirectToken::DEFAULT_TTL).clamp(1, ::Widget::RedirectToken::DEFAULT_TTL)
  end

  # A token only carries the identity of a contact this account already has: the caller names it by
  # contact_id and/or identifier, and every value given must match that same contact.
  def redirect_contact
    @redirect_contact ||= Current.account.contacts.find_by(contact_filters) if contact_filters.present?
  end

  def contact_filters
    { id: permitted_params[:contact_id], identifier: permitted_params[:identifier] }.compact_blank
  end

  def permitted_params
    params.permit(:inbox_id, :contact_id, :identifier, :message, :ttl_seconds)
  end
end
