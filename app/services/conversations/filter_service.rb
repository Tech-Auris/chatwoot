class Conversations::FilterService < FilterService
  ATTRIBUTE_MODEL = 'conversation_attribute'.freeze
  LEGACY_AI_OFF_LABEL = 'agente-off'.freeze

  def initialize(params, user, account)
    @account = account
    super(params, user)
  end

  def perform
    validate_query_operator
    @conversations = query_builder(@filters['conversations'])
    mine_count, unassigned_count, all_count, = set_count_for_all_conversations
    assigned_count = all_count - unassigned_count

    {
      conversations: conversations,
      count: {
        mine_count: mine_count,
        assigned_count: assigned_count,
        unassigned_count: unassigned_count,
        all_count: all_count
      }
    }
  end

  # Accounts that haven't migrated to the `ai_enabled` column still express the
  # AI status through the legacy `agente-off` label, so the filter is rewritten
  # into the equivalent label query for them.
  def build_condition_query_string(current_filter, query_hash, current_index)
    return super unless legacy_ai_status_filter?(query_hash)

    tag_filter_query(legacy_ai_status_query_hash(query_hash), current_index)
  end

  def base_relation
    conversations = @account.conversations.includes(
      :taggings, :inbox, { assignee: { avatar_attachment: [:blob] } }, { contact: { avatar_attachment: [:blob] } }, :team, :messages, :contact_inbox
    )
    # Add an explicit LEFT JOIN so filters that read `contacts.additional_attributes`
    # (e.g. Origem do lead) can reach the column. `.includes` alone preloads via a
    # second SELECT and doesn't put `contacts` in FROM; `.references` on a raw-string
    # WHERE doesn't reliably upgrade it either, so we join outright. Cheap because
    # contact_id is already a FK — one extra LEFT JOIN per query.
    conversations = conversations.left_outer_joins(:contact) if references_contact_attributes?

    Conversations::PermissionFilterService.new(
      conversations,
      @user,
      @account
    ).perform
  end

  def current_page
    @params[:page] || 1
  end

  def filter_config
    {
      entity: 'Conversation',
      table_name: 'conversations'
    }
  end

  def conversations
    @conversations.sort_on_last_activity_at.page(current_page).per(per_page)
  end

  def per_page
    default = ENV.fetch('CONVERSATION_RESULTS_PER_PAGE', '25').to_i
    requested = (@params[:per_page] || default).to_i
    [requested, 100].min
  end

  private

  # Any payload entry that maps to a filter of type `contact_additional_attributes`
  # in filter_keys.yml — right now only `origem`, but new contact-backed
  # conversation filters can register themselves without touching this method.
  def references_contact_attributes?
    # Payload entries can arrive as plain Hash (tests, background jobs) or as
    # ActionController::Parameters (real controller path). The latter is NOT a
    # subclass of Hash, so an `is_a?(Hash)` guard silently drops every entry
    # and the JOIN never happens. `respond_to?(:[])` catches both shapes.
    keys = Array(@params[:payload]).filter_map do |q|
      next unless q.respond_to?(:[])

      q['attribute_key'] || q[:attribute_key]
    end
    conversations_filters = @filters['conversations'] || {}
    keys.any? { |k| conversations_filters.dig(k, 'attribute_type') == 'contact_additional_attributes' }
  end

  def legacy_ai_status_filter?(query_hash)
    query_hash['attribute_key'] == 'ai_enabled' && !@account.ai_status_uses_attribute?
  end

  def legacy_ai_status_query_hash(query_hash)
    enabled = ActiveModel::Type::Boolean.new.cast(Array(query_hash['values']).first)
    enabled = !enabled if query_hash['filter_operator'] == 'not_equal_to'

    query_hash.merge(
      'values' => [LEGACY_AI_OFF_LABEL],
      'filter_operator' => enabled ? 'not_equal_to' : 'equal_to'
    )
  end
end
