namespace :secretary_prompts do
  simulation_note = ' (simulação: nada foi gravado; rode com APPLY=true para importar)'

  desc 'Import (APPLY=true) or compare (default) the Supabase prompt table from a CSV export (CSV=path)'
  task import: :environment do
    apply = ENV['APPLY'] == 'true'
    results = SecretaryPrompts::SupabaseImport.new(csv_path: ENV.fetch('CSV'), apply: apply).perform
    results.each do |result|
      puts [result.id, result.differences.empty? ? 'ok' : "diferente: #{result.differences.join(', ')}"].join(' | ')
    end
    puts "#{results.size} prompts, #{results.count { |result| result.differences.any? }} com diferença#{simulation_note unless apply}"
  end

  desc 'Import (APPLY=true) or compare (default) the account prompts from the Supabase cliente and cliente_inbox_prompt ' \
       'CSV exports (CLIENTE_CSV=path INBOX_CSV=path)'
  task import_account: :environment do
    apply = ENV['APPLY'] == 'true'
    results = AccountPrompts::SupabaseImport.new(cliente_csv_path: ENV.fetch('CLIENTE_CSV'), inbox_csv_path: ENV.fetch('INBOX_CSV'),
                                                 apply: apply).perform
    results.each do |result|
      diff = "#{result.missing&.size} faltando, #{result.extra&.size} sobrando"
      status = result.error || (result.missing.empty? && result.extra.empty? ? 'ok' : diff)
      puts [result.account_id, result.account&.name, "#{result.expected_count} prompts", status].join(' | ')
      result.conflicts&.each { |conflict| puts "  ! conflito, não importado: #{conflict}" }
      result.missing&.each { |(name, _text, ids)| puts "  - falta no Rails: #{name} (inboxes #{ids.join(', ')})" }
      result.extra&.each { |(name, _text, ids)| puts "  + só no Rails: #{name} (inboxes #{ids.join(', ')})" }
    end
    divergent = results.count { |result| result.error || result.conflicts.any? || result.missing.any? || result.extra.any? }
    puts "#{results.size} contas, #{divergent} com diferença ou conflito#{simulation_note unless apply}"
  end
end
