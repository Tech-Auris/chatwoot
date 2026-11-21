# Visão geral of a clinic pipeline: the same table as the Agendamento's
# (V2::Reports::FunnelSummaryBuilder), read off pipeline_entry_events.
class V2::Reports::PipelineSummaryBuilder
  include V2::Reports::PipelineReportScope

  # Time on a stage = until the next move of the same entry, or until now
  # while it is still there. Filtered by when the entry reached the stage.
  AVG_TIME_SQL = <<~SQL.squish.freeze
    WITH ordered AS (
      SELECT
        to_stage_id,
        created_at,
        LEAD(created_at) OVER (PARTITION BY pipeline_entry_id ORDER BY created_at, id) AS next_change_at
      FROM pipeline_entry_events
      WHERE pipeline_id = :pipeline_id
        AND (:has_filter = FALSE OR pipeline_entry_id IN (:entry_ids))
    )
    SELECT to_stage_id, AVG(EXTRACT(EPOCH FROM (COALESCE(next_change_at, NOW()) - created_at))) AS avg_seconds
    FROM ordered
    WHERE created_at >= :since AND created_at < :until_exclusive
    GROUP BY to_stage_id
  SQL

  def build
    in_stage = entries_scope.group(:pipeline_stage_id).count
    entered = distinct_entries_by_stage(events_in_range)
    avg_times = fetch_avg_times
    won, lost = exit_counts

    stages.map do |stage|
      {
        id: stage.id, name: stage.name, color: stage.color, position: stage.position, closed: stage.closing?,
        in_stage_count: in_stage[stage.id] || 0, entered_count: entered[stage.id] || 0,
        avg_time_in_stage: avg_times[stage.id] || 0, won_count: won[stage.id] || 0, lost_count: lost[stage.id] || 0
      }
    end
  end

  private

  # Entries that left each stage straight to Ganho / Perdido in the period.
  def exit_counts
    %i[won lost].map do |kind|
      events_in_range.where(to_stage_id: stages.select { |stage| stage.kind == kind.to_s }.map(&:id))
                     .group(:from_stage_id).count
    end
  end

  def fetch_avg_times
    return {} if range.blank?

    entry_ids = params[:label].present? ? entries_scope.pluck(:id) : []
    sql = ActiveRecord::Base.sanitize_sql_array(
      [AVG_TIME_SQL, { pipeline_id: pipeline.id, has_filter: params[:label].present?, entry_ids: entry_ids.presence || [-1],
                       since: range.first, until_exclusive: range.last }]
    )
    ActiveRecord::Base.connection.select_all(sql).to_h { |row| [row['to_stage_id'], row['avg_seconds'].to_f] }
  end
end
