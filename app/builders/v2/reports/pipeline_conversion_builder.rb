# Conversão of a clinic pipeline: the generic version of the Agendamento's
# report — win rate, loss rate, average time until the win, the funnel chart
# (stage to stage, ending in Ganho) and the loss reasons. No campaign grid:
# that one measures ad leads reaching the Agendamento.
class V2::Reports::PipelineConversionBuilder
  include V2::Reports::PipelineReportScope

  def build
    total = events_in_range.distinct.count(:pipeline_entry_id)
    reached = distinct_entries_by_stage(events_in_range)
    {
      stages: chart_rows(reached, total),
      kpis: kpis(reached, total),
      loss_reasons: loss_reasons
    }
  end

  private

  def won_stage
    stages.find(&:won?)
  end

  def lost_stage
    stages.find(&:lost?)
  end

  # Every entry that moved in the period counts on the first bar, so the
  # funnel never shows a later stage bigger than its start.
  def chart_rows(reached, total)
    chart_stages = stages.reject(&:lost?)
    rows = chart_stages.each_with_index.map do |stage, index|
      count = index.zero? ? total : (reached[stage.id] || 0)
      { id: stage.id, key: stage.name, drillable: false, name: stage.name, color: stage.color, position: stage.position,
        closed: stage.closing?, count: count, count_ai: 0, count_manual: count }
    end
    rows.each_cons(2) { |row, next_row| row.merge!(step_to(row, next_row)) }
    rows
  end

  def step_to(row, next_row)
    { next_stage_id: next_row[:id], next_stage_name: next_row[:name],
      conversion_rate: row[:count].zero? ? nil : rate(next_row[:count], row[:count]),
      drop_off_count: [row[:count] - next_row[:count], 0].max,
      conversion_exceeds_previous: next_row[:count] > row[:count] }
  end

  def kpis(reached, total)
    won = reached[won_stage.id] || 0
    lost = reached[lost_stage.id] || 0
    { total: total, won_count: won, won_rate: rate(won, total), lost_count: lost, lost_rate: rate(lost, total),
      avg_time_to_won: avg_time_to_won }
  end

  # From the moment the contact entered the pipeline to the move to Ganho.
  def avg_time_to_won
    events_in_range.where(to_stage_id: won_stage.id)
                   .joins(:entry)
                   .average('EXTRACT(EPOCH FROM (pipeline_entry_events.created_at - pipeline_entries.created_at))')
                   .to_f
  end

  def loss_reasons
    counts = events_in_range.where(to_stage_id: lost_stage.id).where.not(loss_reason_id: nil)
                            .joins(:loss_reason).group('loss_reasons.id', 'loss_reasons.name')
                            .distinct.count(:pipeline_entry_id)
    total = counts.values.sum
    counts.map { |(id, name), count| { id: id, name: name, count: count, percentage: rate(count, total) } }
          .sort_by { |row| -row[:count] }
  end
end
