# The conversations behind a number of the funnel conversion report: one of
# the chart stages (Agendamento, Confirmado, Comparecimentos) or the lost
# conversations of the loss-reasons donut.
#
# Inherits the report's own scoping (period, inbox / label / origem filters,
# conversations that still exist) so the list always has exactly as many rows
# as the number that was clicked. One row per conversation (its most recent
# entry in the period) — per conversation and reason on the losses, since the
# donut counts a conversation once under each reason it was lost with.
class V2::Reports::FunnelConversionDrilldownBuilder < V2::Reports::FunnelConversionBuilder
  PER_PAGE = 50

  class UnknownStage < StandardError; end

  def build
    entries = latest_entry_per_conversation
    total = entries.count
    page = entries.order(created_at: :desc, id: :desc).page(current_page).per(PER_PAGE).includes(:user, :loss_reason).to_a
    conversations = Conversation.where(id: page.map(&:conversation_id)).includes(:contact, :inbox).index_by(&:id)

    {
      rows: page.map { |entry| row_for(entry, conversations[entry.conversation_id]) },
      meta: { current_page: current_page, per_page: PER_PAGE, total_count: total }
    }
  end

  private

  def latest_entry_per_conversation
    scope = funnel_stage_changes_scope
    scope = scope.where(created_at: range) if range.present?
    scope = loss? ? loss_scope(scope) : scope.where(new_stage: stage_names)
    per = loss? ? 'funnel_stage_changes.conversation_id, funnel_stage_changes.loss_reason_id' : 'funnel_stage_changes.conversation_id'
    latest = scope.select("DISTINCT ON (#{per}) funnel_stage_changes.*").reorder(Arel.sql("#{per}, funnel_stage_changes.created_at DESC"))
    FunnelStageChange.from(latest, :funnel_stage_changes)
  end

  def loss?
    params[:kind] == 'loss'
  end

  def loss_scope(scope)
    params[:loss_reason_id].present? ? scope.where(loss_reason_id: params[:loss_reason_id]) : scope.where.not(loss_reason_id: nil)
  end

  # Same grouping the chart uses, so "Agendamento" means Agendado + Reagendado
  # here exactly as it does on the bar.
  def stage_names
    raise UnknownStage unless DRILLABLE_STAGE_KEYS.include?(params[:stage_key])

    group = build_display_groups(FunnelStage.active.ordered.to_a).find { |g| g[:key] == params[:stage_key] }
    raise UnknownStage if group.nil?

    group[:stage_names]
  end

  def current_page
    [params[:page].to_i, 1].max
  end

  # The scope only keeps conversations that still exist, so every entry has one.
  def row_for(entry, conversation)
    {
      conversation_id: conversation.display_id,
      contact_name: conversation.contact.name,
      contact_phone: conversation.contact.phone_number,
      entered_at: entry.created_at.iso8601,
      stage: entry.new_stage,
      previous_stage: entry.previous_stage,
      moved_by: entry.user&.name,
      inbox_name: conversation.inbox.name,
      origem: conversation.origem,
      ad_title: conversation.additional_attributes&.dig('campaign_referral', 'title'),
      loss_reason: entry.loss_reason&.name
    }
  end
end
