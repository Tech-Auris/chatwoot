# rubocop:disable Metrics/BlockLength
namespace :secretary_confirmations do
  desc 'Import (APPLY=true) or compare (default) the Supabase confirmacoes table from a CSV export (CSV=path)'
  task import: :environment do
    apply = ENV['APPLY'] == 'true'
    results = SecretaryConfirmations::SupabaseImport.new(csv_path: ENV.fetch('CSV'), apply: apply).perform
    results.each do |result|
      diff = "#{result.missing&.size} faltando, #{result.extra&.size} sobrando"
      status = result.error || (result.missing.empty? && result.extra.empty? ? 'ok' : diff)
      puts [result.account_id, result.account&.name, "#{result.csv_count} no CSV", status].join(' | ')
      result.missing&.each { |tuple| puts "  - falta no Rails: #{tuple.first(4).inspect}" }
      result.extra&.each { |tuple| puts "  + só no Rails: #{tuple.first(4).inspect}" }
    end
    divergent = results.count { |result| result.error || result.missing.any? || result.extra.any? }
    puts "#{results.size} contas, #{divergent} com diferença#{' (simulação: nada foi gravado; rode com APPLY=true para importar)' unless apply}"
  end

  desc 'Import (APPLY=true) or compare (default) the Supabase confirmacoes_send_log table from a CSV export (CSV=path)'
  task import_send_log: :environment do
    apply = ENV['APPLY'] == 'true'
    results = SecretaryConfirmations::SendLogImport.new(csv_path: ENV.fetch('CSV'), apply: apply).perform
    results.each do |result|
      status = result.error || (result.rails_count >= result.csv_count ? 'ok' : "#{result.csv_count - result.rails_count} faltando")
      puts [result.account_id, "#{result.csv_count} no CSV", "#{result.rails_count} no Rails", status].compact.join(' | ')
    end
    divergent = results.count { |result| result.error || result.rails_count < result.csv_count }
    puts "#{results.size} contas, #{divergent} com diferença#{' (simulação: nada foi gravado; rode com APPLY=true para importar)' unless apply}"
  end

  desc 'Print as CSV, in the Supabase confirmacoes_send_log columns, the reminders logged in Rails since SINCE (ISO time), for a rollback'
  task export_send_log: :environment do
    puts %w[calendar_id chatwoot_account_id event_id reminder_type sent_at].to_csv
    SecretaryConfirmationSendLog.where(sent_at: Time.zone.parse(ENV.fetch('SINCE'))..).order(:id).find_each do |send_log|
      puts [send_log.calendar_id, send_log.account_id, send_log.event_id, send_log.reminder_type, send_log.sent_at.iso8601(6)].to_csv
    end
  end
end
# rubocop:enable Metrics/BlockLength
