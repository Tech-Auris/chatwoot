require 'csv'

# The CSV of the change history ("Exportar CSV"), with the filters the admin
# applied, newest first, in São Paulo time. Each change is one
# "field: before → after" line in the last column.
class ActivityLogs::ExportService
  LIMIT = 10_000
  TIME_ZONE = 'America/Sao_Paulo'.freeze
  BOM = "\xEF\xBB\xBF".freeze
  COLUMNS = %w[date actor source action record_type record_id record ip changes].freeze

  pattr_initialize [:scope!]

  def perform
    "#{BOM}#{csv}"
  end

  def filename
    "historico-de-alteracoes-#{Time.zone.today}.csv"
  end

  private

  def csv
    CSV.generate do |output|
      output << COLUMNS.map { |column| I18n.t("activity_logs.export.columns.#{column}") }
      scope.recent_first.limit(LIMIT).each { |log| output << row_for(log) }
    end
  end

  def row_for(log)
    [
      log.created_at.in_time_zone(TIME_ZONE).strftime('%d/%m/%Y %H:%M:%S'),
      log.actor_label.presence || I18n.t('activity_logs.system'),
      I18n.t("activity_logs.sources.#{log.source}"),
      I18n.t("activity_logs.actions.#{log.action}"),
      log.auditable_type, log.auditable_id, log.auditable_label, log.ip_address,
      changes_text(log.audited_changes)
    ]
  end

  def changes_text(changes)
    changes.map do |field, (before, after)|
      next "#{field}: #{I18n.t('activity_logs.filtered')}" if after == ActivityLog::FILTERED

      "#{field}: #{format_value(before)} → #{format_value(after)}"
    end.join("\n")
  end

  def format_value(value)
    return '—' if value.nil? || value == ''

    value.is_a?(String) ? value : value.to_json
  end
end
