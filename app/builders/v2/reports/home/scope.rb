# What the Início page counts: the conversations of the caixas in view (always
# within the ones the user can see) and never WhatsApp groups, optionally of a
# single origem. Every number on the page is built on top of this.
class V2::Reports::Home::Scope
  DEFAULT_TIMEZONE = 'America/Sao_Paulo'.freeze

  attr_reader :account, :inbox_ids, :origem

  def initialize(account:, inbox_ids:, origem: nil)
    @account = account
    @inbox_ids = inbox_ids
    @origem = origem.presence
  end

  def conversations
    scope = account.conversations.where(inbox_id: inbox_ids).group_type_individual
    return scope if origem.nil?
    return scope.where("conversations.origem IS NULL OR conversations.origem = ''") if origem == none_token

    scope.where(origem: origem)
  end

  # Stage changes of conversations still in the scope, the same source the
  # Conversão do funil report counts from.
  def stage_changes(stage_names)
    account.funnel_stage_changes.where(new_stage: stage_names, conversation_id: conversations.select(:id))
  end

  def scheduling_stage_names
    @scheduling_stage_names ||= FunnelStage.active
                                           .where(chart_group: V2::Reports::FunnelConversionBuilder::SCHEDULING_CHART_GROUP)
                                           .pluck(:name)
  end

  def zone
    @zone ||= ActiveSupport::TimeZone[account.reporting_timezone.presence || DEFAULT_TIMEZONE]
  end

  private

  def none_token
    V2::Reports::FunnelConversionBuilder::ORIGEM_NONE_TOKEN
  end
end
