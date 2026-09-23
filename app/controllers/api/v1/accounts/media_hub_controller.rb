# Powers the "Mídia" screen on the left-nav — pulls every attachment / link
# the account has produced across the conversations the current user can
# see, so the operator finds "that PDF the customer sent last week" without
# opening every thread.
#
# One endpoint, five faces via `type`:
#   - image / video / audio → attachment grids per media kind
#   - document              → file attachments (table view)
#   - link                  → URLs mined from message content (table view)
#
# Kept as an index-only controller so the client never has to hit a second
# call; grouping into "Hoje / Ontem / Esta semana / …" happens on the front
# because it's a display concern (localized labels).
#
# Inbox scoping matches the rest of the dashboard: `assigned_inboxes` gives
# a manager / administrator every inbox in the account, and an agent only
# the inboxes they are a member of — so an agent can't discover attachments
# from a conversation they cannot open.
class Api::V1::Accounts::MediaHubController < Api::V1::Accounts::BaseController
  PER_PAGE = 60
  URL_REGEX = %r{https?://[^\s<>"']+}
  MEDIA_KINDS = %w[image video audio].freeze

  def index
    render json: {
      items: serialize_items,
      meta: {
        current_page: current_page,
        total_pages: (total_count.to_f / PER_PAGE).ceil,
        total_count: total_count,
        type: kind
      }
    }
  end

  # Bulk-delete driven by the Media Hub's context menu / bottom shelf.
  # Media and Document rows carry attachment ids; Links carry message
  # ids (a link "row" is a URL extracted from a message's content, so
  # deleting it means dropping the parent message). Attachments whose
  # host message ends up empty are cleaned up along the way so we don't
  # leave dangling ghost messages behind.
  def destroy
    ids = Array(params[:ids]).map(&:to_i).uniq
    return render(json: { deleted: 0 }) if ids.empty?

    deleted = kind == 'link' ? delete_link_messages(ids) : delete_attachments(ids)
    render json: { deleted: deleted }
  end

  private

  def delete_attachments(attachment_ids)
    scope = Attachment.where(account_id: Current.account.id, id: attachment_ids)
                      .joins(message: :conversation)
                      .where(conversations: { inbox_id: accessible_inbox_ids })
                      .includes(:message)
    count = 0
    scope.find_each do |att|
      message = att.message
      att.destroy!
      # Drop the parent message when it becomes empty — no other
      # attachments and no text content. Prevents orphan bubbles that
      # only carried the one asset the operator just removed.
      message.destroy! if message && message.reload.attachments.empty? && message.content.to_s.strip.empty?
      count += 1
    end
    count
  end

  def delete_link_messages(message_ids)
    scope = Current.account.messages
                   .joins(:conversation)
                   .where(id: message_ids, conversations: { inbox_id: accessible_inbox_ids })
    count = scope.count
    scope.find_each(&:destroy!)
    count
  end

  def kind
    @kind ||= (params[:type].presence || 'image').to_s
  end

  # Inboxes the current user can see. Manager / administrator get every
  # inbox in the account; an agent gets only the inboxes they belong to
  # via `inbox_members`. See `User#assigned_inboxes` for the source of
  # this rule — reused here so the Media Hub matches the same access
  # boundary the conversation list enforces.
  def accessible_inbox_ids
    @accessible_inbox_ids ||= Current.user.assigned_inboxes.pluck(:id)
  end

  def current_page
    @current_page ||= [params[:page].to_i, 1].max
  end

  def serialize_items
    case kind
    when 'link' then serialize_links
    else serialize_attachments
    end
  end

  # `media` and `document` both live on `attachments`; only `file_type` and
  # the sub-includes change. Kept as one method so the sort / pagination
  # story stays identical.
  def serialize_attachments
    paginated_attachments.map { |att| serialize_attachment(att) }
  end

  def serialize_attachment(attachment)
    message = attachment.message
    conversation = message&.conversation
    sender = message&.sender

    {
      id: attachment.id,
      message_id: message&.id,
      conversation_id: conversation&.display_id,
      created_at: message&.created_at,
      file_type: attachment.file_type,
      file_size: attachment.meta&.dig('file_size'),
      extension: attachment.extension,
      # `download_url` is empty when the attachment is a link (external_url,
      # WhatsApp media, etc.); fall back to the raw external URL so the hub
      # keeps working across the full mix of upload styles.
      file_url: attachment.download_url.presence || attachment.external_url,
      thumb_url: attachment.thumb_url.presence || attachment.external_url,
      fallback_title: attachment.fallback_title,
      caption: message&.content.to_s.strip.presence,
      sender_name: sender_name(message, sender),
      sender_avatar: sender_avatar_url(sender)
    }
  end

  def paginated_attachments
    scope = Attachment.where(account_id: Current.account.id)
                      .where(file_type: attachment_types_for_kind)
                      .joins(message: :conversation)
                      .where(conversations: { inbox_id: accessible_inbox_ids })
                      .preload(message: [:conversation, :sender])
                      .order('messages.created_at DESC')

    @attachment_total = scope.count
    scope.offset((current_page - 1) * PER_PAGE).limit(PER_PAGE)
  end

  def attachment_types_for_kind
    case kind
    when 'document' then [Attachment.file_types[:file]]
    when 'video'    then [Attachment.file_types[:video]]
    when 'audio'    then [Attachment.file_types[:audio]]
    else                 [Attachment.file_types[:image]]
    end
  end

  # Extracts every URL out of recent messages. Not indexable so a full scan
  # of every message row would cripple the DB — we cap the window at the
  # most recent 1000 non-empty messages and dedupe URLs per message.
  def serialize_links
    return @serialize_links if defined?(@serialize_links)

    # Message has a `default_scope { order(created_at: :asc) }` — we need
    # `reorder` (not `order`) to actually get the newest messages first.
    # `preload` (not `includes`) — the join on `conversations` combined with
    # a polymorphic `:sender` would trip `ActiveRecord::EagerLoadPolymorphicError`
    # if we let Rails infer a JOIN-based eager load.
    rows = Current.account.messages
                  .joins(:conversation)
                  .where(conversations: { inbox_id: accessible_inbox_ids })
                  .where.not(content: [nil, ''])
                  .preload(:conversation, :sender)
                  .reorder(created_at: :desc)
                  .limit(1000)
                  .flat_map { |m| link_rows_for(m) }

    @link_total = rows.length
    @serialize_links = rows[(current_page - 1) * PER_PAGE, PER_PAGE] || []
  end

  def link_rows_for(message)
    urls = message.content.to_s.scan(URL_REGEX).uniq
    return [] if urls.empty?

    urls.map do |url|
      {
        id: "#{message.id}-#{Digest::SHA1.hexdigest(url)[0, 8]}",
        message_id: message.id,
        conversation_id: message.conversation&.display_id,
        created_at: message.created_at,
        url: url,
        host: begin
          URI.parse(url).host
        rescue StandardError
          nil
        end,
        caption: message.content.to_s.strip,
        sender_name: sender_name(message, message.sender),
        sender_avatar: sender_avatar_url(message.sender)
      }
    end
  end

  def total_count
    case kind
    when 'link' then @link_total || 0
    else @attachment_total || 0
    end
  end

  # A message can be sent by a Contact (the customer), a User (an agent) or
  # by a bot / API integration. Anything without a linked sender is labeled
  # "Você" following the convention we already use across the dashboard.
  def sender_name(message, sender)
    return sender.name if sender.respond_to?(:name) && sender.name.present?
    return sender.email if sender.respond_to?(:email) && sender.email.present?
    return message.sender_type if message.respond_to?(:sender_type) && message.sender_type.present?

    'Você'
  end

  def sender_avatar_url(sender)
    return nil unless sender.respond_to?(:avatar_url)

    sender.avatar_url.presence
  end
end
