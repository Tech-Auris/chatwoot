class Api::V1::Widget::RedirectTokensController < Api::V1::Widget::BaseController
  include WidgetHelper

  def create
    payload = ::Widget::RedirectToken.consume(permitted_params[:token])
    return render(json: { error: 'invalid_token' }, status: :not_found) if payload.blank?
    return render(json: { error: 'invalid_token' }, status: :not_found) if payload['inbox_id'] != @web_widget.inbox.id

    identify_from_token(payload)
    resume_or_start_conversation(payload)

    render json: {
      widget_auth_token: @widget_auth_token,
      conversation_id: @conversation&.display_id
    }
  end

  private

  # The token names a contact the account confirmed when minting it, and the session joins that
  # contact. A browser that is already somebody else starts a fresh session first, so it is never
  # merged away.
  def identify_from_token(payload)
    target = account.contacts.find_by(id: payload['contact_id']) if payload['contact_id'].present?
    if target.present? && target.id != @contact.id && established_identity?
      @contact_inbox, @widget_auth_token = build_contact_inbox_with_token(@web_widget)
      @contact = @contact_inbox.contact
    end
    @contact_inbox.update!(hmac_verified: true)
    return if target.blank?

    @contact = ContactMergeAction.new(account: account, base_contact: target, mergee_contact: @contact).perform
  end

  def established_identity?
    @contact.identifier.present? || @contact.email.present? || @contact.phone_number.present?
  end

  def account
    @web_widget.inbox.account
  end

  def resume_or_start_conversation(payload)
    if payload['message'].present?
      @conversation = conversations.where.not(status: :resolved).last || start_conversation
      inject_cloned_message(payload['message'])
    else
      @conversation = conversations.last || start_conversation
    end
  end

  def start_conversation
    ::Conversation.create!(
      account_id: @web_widget.inbox.account_id,
      inbox_id: @web_widget.inbox.id,
      contact_id: @contact.id,
      contact_inbox_id: @contact_inbox.id
    )
  end

  def inject_cloned_message(content)
    @conversation.messages.create!(
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      sender: @contact,
      content: content,
      message_type: :incoming
    )
  end

  def permitted_params
    params.permit(:website_token, :token)
  end
end
