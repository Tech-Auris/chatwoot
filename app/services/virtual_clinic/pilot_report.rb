# Numbers of the Clínica virtual pilot, per account and persona: questions,
# failures, answer time (p50/p90), tokens and the tools the AI used most.
class VirtualClinic::PilotReport
  HEADERS = %w[account_id account persona questions failed_pct p50_seconds p90_seconds avg_input_tokens avg_output_tokens top_tools].freeze

  def initialize(since:)
    @since = since
  end

  def rows
    answers.group_by { |answer| [answer.thread.account, answer.thread.persona] }.map do |(account, persona), group|
      seconds = group.select(&:done?).map { |answer| (answer.updated_at - answer.created_at).round }.sort
      [account.id, account.name, persona, group.size, failed_pct(group), percentile(seconds, 50), percentile(seconds, 90),
       average(group, :input_tokens), average(group, :output_tokens), top_tools(group)]
    end
  end

  def to_csv
    CSV.generate { |csv| [HEADERS, *rows].each { |row| csv << row } }
  end

  private

  def answers
    VirtualClinicMessage.assistant.where(created_at: @since..).where.not(status: :pending).includes(thread: :account)
  end

  def failed_pct(group)
    (group.count(&:failed?) * 100.0 / group.size).round(1)
  end

  def percentile(sorted, pct)
    return nil if sorted.empty?

    sorted[((pct / 100.0) * sorted.size).ceil - 1]  # nearest rank
  end

  def average(group, column)
    values = group.filter_map(&column)
    values.empty? ? nil : (values.sum / values.size)
  end

  def top_tools(group)
    group.flat_map { |answer| answer.tool_calls.pluck('name') }.tally.max_by(3, &:last).map(&:first).join(' ')
  end
end
