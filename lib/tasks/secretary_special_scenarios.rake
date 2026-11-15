namespace :secretary_special_scenarios do
  desc 'Import (APPLY=true) or compare (default) the Supabase special_scenarios table from a CSV export (CSV=path)'
  task import: :environment do
    apply = ENV['APPLY'] == 'true'
    results = SecretarySpecialScenarios::SupabaseImport.new(csv_path: ENV.fetch('CSV'), apply: apply).perform
    results.each do |result|
      diff = "#{result.missing&.size} faltando, #{result.extra&.size} sobrando"
      status = result.error || (result.missing.empty? && result.extra.empty? ? 'ok' : diff)
      puts [result.account_id, result.account&.name, "#{result.csv_count} no CSV", status].join(' | ')
      result.missing&.each { |tuple| puts "  - falta no Rails: #{tuple.first}" }
      result.extra&.each { |tuple| puts "  + só no Rails: #{tuple.first}" }
    end
    divergent = results.count { |result| result.error || result.missing.any? || result.extra.any? }
    puts "#{results.size} contas, #{divergent} com diferença#{' (simulação: nada foi gravado; rode com APPLY=true para importar)' unless apply}"
  end

  desc 'Print the cache_supabase_special_scenarios value Rails builds for one account (ACCOUNT_ID=id), to diff against the one in Redis'
  task cache_payload: :environment do
    puts JSON.generate(SecretarySpecialScenario.cache_payload(ENV.fetch('ACCOUNT_ID').to_i))
  end
end
