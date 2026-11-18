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

  desc 'Import (APPLY=true) or compare (default) the Supabase cliente_inbox_prompt table from a CSV export (CSV=path)'
  task import_inbox: :environment do
    apply = ENV['APPLY'] == 'true'
    results = InboxPrompts::SupabaseImport.new(csv_path: ENV.fetch('CSV'), apply: apply).perform
    results.each do |result|
      diff = "#{result.missing&.size} faltando, #{result.extra&.size} sobrando"
      status = result.error || (result.missing.empty? && result.extra.empty? ? 'ok' : diff)
      puts [result.account_id, result.account&.name, "#{result.csv_count} no CSV", status].join(' | ')
      result.conflicts&.each { |conflict| puts "  ! conflito, não importado: #{conflict}" }
      result.missing&.each { |(_text, ids)| puts "  - falta no Rails: inboxes #{ids.join(', ')}" }
      result.extra&.each { |(_text, ids)| puts "  + só no Rails: inboxes #{ids.join(', ')}" }
    end
    divergent = results.count { |result| result.error || result.conflicts.any? || result.missing.any? || result.extra.any? }
    puts "#{results.size} contas, #{divergent} com diferença ou conflito#{simulation_note unless apply}"
  end
end
