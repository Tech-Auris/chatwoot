namespace :secretary_resources do
  desc 'Import (APPLY=true) or compare (default) the Supabase resource table from a CSV export (CSV=path)'
  task import: :environment do
    apply = ENV['APPLY'] == 'true'
    results = SecretaryResources::SupabaseImport.new(csv_path: ENV.fetch('CSV'), apply: apply).perform
    results.each do |result|
      diff = "#{result.missing&.size} faltando, #{result.extra&.size} sobrando"
      status = result.error || (result.missing.empty? && result.extra.empty? ? 'ok' : diff)
      puts [result.account_id, result.account&.name, "#{result.csv_count} no CSV", status].join(' | ')
      result.missing&.each { |tuple| puts "  - falta no Rails: #{tuple.inspect}" }
      result.extra&.each { |tuple| puts "  + só no Rails: #{tuple.inspect}" }
    end
    divergent = results.count { |result| result.error || result.missing.any? || result.extra.any? }
    puts "#{results.size} contas, #{divergent} com diferença#{' (simulação: nada foi gravado; rode com APPLY=true para importar)' unless apply}"
  end
end
