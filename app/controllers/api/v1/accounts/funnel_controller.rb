class Api::V1::Accounts::FunnelController < Api::V1::Accounts::BaseController
  before_action :authorize_funnel

  # First-page cap per stage. The board renders every stage side by side,
  # so what used to be "hydrate everything" easily became "hydrate a few
  # thousand cards" on a busy account, driving `_conversation.json.jbuilder`
  # into thousands of tag / loss-reason queries and blowing past the DB
  # statement timeout. Extra pages come in through `#stage_conversations`.
  DEFAULT_PER_PAGE = 25
  MAX_PER_PAGE = 100

  def show
    @stages = FunnelStage.active.ordered
    relation = filtered_conversations
    @conversations_by_stage, @stage_totals = paginate_by_stage(relation, per_page)
    @loss_reasons_by_conversation_id = loss_reasons_by_conversation_id(@conversations_by_stage.values.flatten)
  end

  # Next page of a single stage — hit by the "Carregar mais" button at
  # the bottom of a column on the board.
  def stage_conversations
    @stage = FunnelStage.active.find(params[:stage_id])
    relation = filtered_conversations.where(funnel_stage_id: @stage.id)
    @total = relation.count
    @per_page = per_page
    @current_page = current_page
    offset = (@current_page - 1) * @per_page
    @conversations = relation.order(last_activity_at: :desc)
                             .offset(offset)
                             .limit(@per_page)
                             .to_a
    @has_more = (offset + @conversations.size) < @total
    @stages = [@stage]
    @loss_reasons_by_conversation_id = loss_reasons_by_conversation_id(@conversations)
  end

  def move
    service = Funnel::MoveConversationService.new(
      account: Current.account,
      conversation_display_id: params.require(:conversation_id),
      # `stage` (name) is what the kanban sends; `funnel_stage_id` is the stable
      # handle the conversation header uses.
      target_stage_name: params[:stage],
      target_stage_id: params[:funnel_stage_id],
      user: Current.user,
      reason: params[:reason],
      source: params[:source] || 'web',
      loss_reason_id: params[:loss_reason_id]
    )
    @result = service.perform
    render :show_move
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def history
    conversation = Current.account.conversations.find_by!(display_id: params.require(:conversation_id))
    @history = Current.account.funnel_stage_changes
                      .where(conversation_id: conversation.id)
                      .order(created_at: :desc)
                      .limit(200)
  end

  def conversation_status
    conversation = Current.account.conversations.find_by!(display_id: params.require(:conversation_id))
    @conversation = conversation
    @stage = conversation.funnel_stage
  end

  private

  def authorize_funnel
    authorize :funnel, :"#{action_name}?"
  end

  ORIGEM_NONE_TOKEN = '__none__'.freeze

  def filtered_conversations
    relation = scoped_conversations
    relation = relation.where('conversations.created_at >= ?', from_date) if from_date.present?
    relation = relation.where('conversations.created_at <= ?', to_date) if to_date.present?
    relation = relation.where(inbox_id: params[:inbox_id]) if params[:inbox_id].present?
    relation = apply_origem_filter(relation) if params[:origem].present?
    relation = relation.where.not(funnel_stage_id: closed_stage_ids) if hide_closed?
    relation
  end

  # The origem filter scopes the board / list to conversations that carry the
  # selected origem on their own column (or, with ORIGEM_NONE_TOKEN, that
  # have no origem attributed yet). Per-conversation matches what "conversas
  # do Google" means to the operator — see feat/conversation-origem-foundation.
  def apply_origem_filter(relation)
    origem = params[:origem].to_s
    if origem == ORIGEM_NONE_TOKEN
      relation.where('conversations.origem IS NULL OR conversations.origem = ?', '')
    else
      relation.where(conversations: { origem: origem })
    end
  end

  def scoped_conversations
    # Preload every association the partial touches — otherwise `label_list`,
    # `funnel_stage`, `account.ai_status_uses_attribute?`, and each
    # contact's `avatar_url` (an ActiveStorage attachment lookup) each ran
    # once per card, which is what pushed the endpoint past the statement
    # timeout on busy accounts.
    Current.account.conversations
           .includes(:inbox, :funnel_stage, :account, contact: { avatar_attachment: :blob })
           .where(funnel_stage_id: active_stage_ids)
  end

  def active_stage_ids
    @active_stage_ids ||= FunnelStage.active.pluck(:id)
  end

  def closed_stage_ids
    @closed_stage_ids ||= FunnelStage.active.closed_stages.pluck(:id)
  end

  # Returns `[conversations_by_stage_id, totals_by_stage_id]`. Counts run
  # in a single grouped query; each stage's page runs as a separate small
  # `ORDER BY last_activity_at DESC LIMIT per_page` query, which the DB
  # planner handles well through the existing `funnel_stage_id` index.
  def paginate_by_stage(relation, per_page)
    totals = relation.group(:funnel_stage_id).count
    by_stage = {}
    @stages.each do |stage|
      total = totals[stage.id] || 0
      by_stage[stage.id] = if total.positive?
                             relation.where(funnel_stage_id: stage.id)
                                     .order(last_activity_at: :desc)
                                     .limit(per_page)
                                     .to_a
                           else
                             []
                           end
    end
    [by_stage, totals]
  end

  # Batches the loss-reason lookup for every conversation currently on the
  # board, so the partial does not run a `funnel_stage_changes` query per
  # card. `funnel_stage_changes.new_stage` is a string (the stage name at
  # the time of the change), so the batch query matches on names.
  def loss_reasons_by_conversation_id(conversations)
    target_conversations = conversations_on_loss_stages(conversations)
    return {} if target_conversations.empty?

    latest = latest_loss_change_timestamps(target_conversations)
    changes = latest_loss_changes(latest)

    changes.index_by(&:conversation_id).transform_values(&:loss_reason)
  end

  def conversations_on_loss_stages(conversations)
    return [] if conversations.blank?

    loss_stage_ids = @stages.select(&:requires_loss_reason?).map(&:id)
    return [] if loss_stage_ids.empty?

    conversations.select { |c| loss_stage_ids.include?(c.funnel_stage_id) }
  end

  def latest_loss_change_timestamps(target_conversations)
    stage_names_by_id = @stages.select(&:requires_loss_reason?).index_by(&:id).transform_values(&:name)
    conversation_ids = target_conversations.map(&:id)
    stage_names = target_conversations.map { |c| stage_names_by_id[c.funnel_stage_id] }.uniq

    Current.account.funnel_stage_changes
           .where(conversation_id: conversation_ids, new_stage: stage_names)
           .group(:conversation_id)
           .maximum(:created_at)
  end

  def latest_loss_changes(timestamps)
    Current.account.funnel_stage_changes
           .includes(:loss_reason)
           .where(conversation_id: timestamps.keys)
           .where(created_at: timestamps.values)
  end

  def from_date
    @from_date ||= parse_time(params[:from])
  end

  def to_date
    @to_date ||= parse_time(params[:to])
  end

  def parse_time(value)
    return if value.blank?

    Time.zone.parse(value)
  rescue ArgumentError
    nil
  end

  def hide_closed?
    ActiveModel::Type::Boolean.new.cast(params[:hide_closed])
  end

  def current_page
    @current_page ||= [params[:page].to_i, 1].max
  end

  def per_page
    return @per_page if defined?(@per_page)

    requested = params[:per_page].to_i
    @per_page = (requested.positive? ? requested : DEFAULT_PER_PAGE).clamp(1, MAX_PER_PAGE)
  end
end
