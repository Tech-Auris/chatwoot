# Account-wide read of every scheduled message the current user can see —
# what powers the new "Mensagens → Agendadas" left-nav entry. The existing
# per-conversation controller stays as-is for create / update / destroy;
# this one is index-only so the operator has one place to check "who has
# something scheduled" without opening every thread.
#
# Inbox scoping follows the rule the rest of the dashboard uses —
# `assigned_inboxes` gives managers / administrators every inbox on the
# account and agents only the ones they belong to via `inbox_members`.
class Api::V1::Accounts::ScheduledMessagesController < Api::V1::Accounts::BaseController
  include Events::Types

  PER_PAGE = 25
  # Statuses the panel can filter on. `draft` is bench work that never fires
  # and is left out; `held` covers agent-suspended plus the auto-hold that
  # kicks in when the customer replies.
  ALLOWED_STATUSES = %w[pending sent failed held].freeze
  DEFAULT_STATUS = 'pending'.freeze

  def index
    render json: {
      items: serialize_items,
      meta: {
        current_page: current_page,
        total_pages: (@total.to_f / PER_PAGE).ceil,
        total_count: @total,
        status: status_filter
      }
    }
  end

  # Creates a scheduled message straight from the account-wide panel —
  # no conversation id required. Given a `contact_id + inbox_id` we
  # find-or-create the ContactInbox and reuse an open conversation for
  # that pair, else create one via `ConversationBuilder`. The result
  # feeds into the per-conversation ScheduledMessage create path so the
  # rest of the stack behaves the same as if the message had been
  # scheduled from the conversation drawer.
  def create
    contact = Current.account.contacts.find_by(id: params[:contact_id])
    return render(json: { error: 'contact_not_found' }, status: :not_found) if contact.blank?

    inbox = accessible_inbox_by_id(params[:inbox_id])
    return render(json: { error: 'inbox_not_accessible' }, status: :forbidden) if inbox.blank?

    conversation = resolve_conversation(contact: contact, inbox: inbox)
    scheduled_message = build_scheduled_message(conversation, inbox)
    return render_scheduled_message_errors(scheduled_message) unless scheduled_message.persisted?

    Rails.configuration.dispatcher.dispatch(
      Events::Types::SCHEDULED_MESSAGE_CREATED,
      Time.zone.now,
      scheduled_message: scheduled_message
    )
    render json: { id: scheduled_message.id, conversation_id: conversation.display_id }
  end

  # Cancels a pending scheduled message from the panel. Uses the same
  # inbox-scope check as `index` — if the record does not live in one of
  # the user's `assigned_inboxes`, we answer 404 rather than expose that
  # the id exists. Only pending rows can be cancelled; sent/failed are
  # already terminal and held ones are the operator's chosen "pause",
  # so blocking cancel on them keeps this endpoint's intent narrow.
  def destroy
    scheduled_message = ScheduledMessage.where(account_id: Current.account.id)
                                        .joins(conversation: :inbox)
                                        .where(conversations: { inbox_id: accessible_inbox_ids })
                                        .find_by(id: params[:id])
    return render(json: { error: 'not_found' }, status: :not_found) if scheduled_message.blank?
    return render(json: { error: 'not_pending' }, status: :unprocessable_entity) unless scheduled_message.pending?

    scheduled_message.destroy!
    Rails.configuration.dispatcher.dispatch(
      Events::Types::SCHEDULED_MESSAGE_DELETED,
      Time.zone.now,
      scheduled_message: scheduled_message
    )
    render json: { deleted: 1 }
  end

  private

  def serialize_items
    paginated.map { |sm| serialize(sm) }
  end

  def paginated
    scope = ScheduledMessage.where(account_id: Current.account.id, status: status_filter)
                            .joins(conversation: :inbox)
                            .where(conversations: { inbox_id: accessible_inbox_ids })
                            .preload(:conversation, :inbox, :author)
                            .order(scheduled_at: :asc)

    @total = scope.count
    scope.offset((current_page - 1) * PER_PAGE).limit(PER_PAGE)
  end

  def serialize(scheduled_message)
    conversation = scheduled_message.conversation
    contact = conversation&.contact
    inbox = scheduled_message.inbox
    author = scheduled_message.author

    {
      id: scheduled_message.id,
      status: scheduled_message.status,
      scheduled_at: scheduled_message.scheduled_at&.iso8601,
      content: scheduled_message.content,
      hold_on_reply: scheduled_message.hold_on_reply,
      conversation_id: conversation&.display_id,
      conversation_status: conversation&.status,
      contact: contact ? { id: contact.id, name: contact.name, phone_number: contact.phone_number, thumbnail: contact.avatar_url } : nil,
      inbox: inbox ? { id: inbox.id, name: inbox.name, channel_type: inbox.channel_type } : nil,
      author: author_payload(author, scheduled_message),
      recurring_scheduled_message_id: scheduled_message.recurring_scheduled_message_id,
      created_at: scheduled_message.created_at.to_i
    }
  end

  def author_payload(author, scheduled_message)
    return nil if author.nil?
    return { id: author.id, type: 'User', name: author.name, avatar: author.avatar_url.presence } if author.is_a?(User)

    { id: scheduled_message.author_id, type: scheduled_message.author_type, name: author.respond_to?(:name) ? author.name : nil }
  end

  def status_filter
    requested = params[:status].to_s
    ALLOWED_STATUSES.include?(requested) ? requested : DEFAULT_STATUS
  end

  def current_page
    @current_page ||= [params[:page].to_i, 1].max
  end

  def accessible_inbox_ids
    @accessible_inbox_ids ||= Current.user.assigned_inboxes.pluck(:id)
  end

  def accessible_inbox_by_id(inbox_id)
    return nil if inbox_id.blank?

    Current.user.assigned_inboxes.find_by(id: inbox_id)
  end

  # Reuse an existing open conversation for the (contact, inbox) pair
  # so a fresh scheduled message does not spawn a duplicate thread when
  # a live one is already there. Only `open` — a snoozed / resolved
  # conversation was closed by the operator and would be a surprise
  # place for a message to land later.
  def resolve_conversation(contact:, inbox:)
    contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: inbox).perform
    existing = Current.account.conversations
                      .where(contact_inbox_id: contact_inbox.id, status: :open)
                      .order(created_at: :desc)
                      .first
    return existing if existing.present?

    ConversationBuilder.new(
      params: ActionController::Parameters.new(
        inbox_id: inbox.id,
        contact_id: contact.id,
        source_id: contact_inbox.source_id,
        assignee_id: Current.user.id,
        status: 'open'
      ),
      contact_inbox: contact_inbox
    ).perform
  end

  # A WhatsApp Cloud sale scheduled outside the 24h window can only
  # dispatch as an approved template; the model's `content_optional?`
  # already accepts a blank `content` when `template_params` is present,
  # and the send job passes `template_params` down to MessageBuilder,
  # which routes to the template path. All this needs on the panel side
  # is to accept the nested hash from the form.
  def build_scheduled_message(conversation, inbox)
    conversation.scheduled_messages.create(
      account: Current.account,
      inbox: inbox,
      author: Current.user,
      content: params[:content],
      template_params: scheduled_message_template_params,
      scheduled_at: params[:scheduled_at],
      hold_on_reply: ActiveModel::Type::Boolean.new.cast(params[:hold_on_reply]) || false,
      status: :pending
    )
  end

  def scheduled_message_template_params
    permitted = params.permit(template_params: {}).to_h[:template_params]
    permitted.presence
  end

  def render_scheduled_message_errors(scheduled_message)
    render json: { errors: scheduled_message.errors.full_messages }, status: :unprocessable_entity
  end
end
