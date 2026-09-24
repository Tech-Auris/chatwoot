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
end
