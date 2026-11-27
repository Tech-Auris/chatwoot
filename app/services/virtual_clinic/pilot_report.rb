# Numbers of the Clínica virtual pilot, per account, persona and model:
# questions, failures, answer time (p50/p90), OpenAI calls and tokens per
# answer, what a question cost in US$ (average, p50, p90 and total) and the
# tools the AI used most.
#
# Only the questions people asked count: what a teammate answered to another
# (AskTeammateTool) goes into the cost of the question that asked for it.
class VirtualClinic::PilotReport
  HEADERS = %w[account_id account persona model questions failed_pct p50_seconds p90_seconds avg_llm_calls avg_input_tokens
               avg_cached_tokens avg_output_tokens avg_cost_usd p50_cost_usd p90_cost_usd total_cost_usd top_tools].freeze

  def initialize(since:)
    @since = since
  end

  def rows
    answers.group_by { |answer| [answer.thread.account, answer.thread.persona, answer.model] }.map do |(account, persona, model), group|
      seconds = group.select(&:done?).map { |answer| (answer.updated_at - answer.created_at).round }.sort
      [account.id, account.name, persona, model, group.size, failed_pct(group), percentile(seconds, 50), percentile(seconds, 90),
       *usage_columns(group), *cost_columns(group), top_tools(group)]
    end
  end

  def to_csv
    CSV.generate { |csv| [HEADERS, *rows].each { |row| csv << row } }
  end

  private

  def answers
    VirtualClinicMessage.assistant.joins(:thread).where(virtual_clinic_threads: { parent_message_id: nil })
                        .where(created_at: @since..).where.not(status: :pending).includes(thread: :account)
  end

  # What the teammates' answers cost, per question that asked for them.
  def delegated_costs
    @delegated_costs ||= VirtualClinicMessage.assistant.joins(:thread).where.not(virtual_clinic_threads: { parent_message_id: nil })
                                             .where(created_at: @since..).group('virtual_clinic_threads.parent_message_id').sum(:cost_usd)
  end

  def usage_columns(group)
    [average(group, :llm_calls, 1), average(group, :input_tokens), average(group, :cached_tokens), average(group, :output_tokens)]
  end

  # Answers from before the cost was stored are left out.
  def cost_columns(group)
    costs = group.filter_map { |answer| answer.cost_usd && (answer.cost_usd + delegated_costs.fetch(answer.id, 0)).to_f }.sort
    return [nil] * 4 if costs.empty?

    [(costs.sum / costs.size).round(6), percentile(costs, 50), percentile(costs, 90), costs.sum.round(6)]
  end

  def failed_pct(group)
    (group.count(&:failed?) * 100.0 / group.size).round(1)
  end

  def percentile(sorted, pct)
    return nil if sorted.empty?

    sorted[((pct / 100.0) * sorted.size).ceil - 1]  # nearest rank
  end

  def average(group, column, digits = 0)
    values = group.filter_map(&column)
    values.empty? ? nil : (values.sum.to_f / values.size).round(digits)
  end

  def top_tools(group)
    group.flat_map { |answer| answer.tool_calls.pluck('name') }.tally.max_by(3, &:last).map(&:first).join(' ')
  end
end
