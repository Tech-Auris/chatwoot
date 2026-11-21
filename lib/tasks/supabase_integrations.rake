namespace :supabase do
  report = lambda do |results|
    results.each do |result|
      status = result.error || (result.differences.empty? ? 'ok' : "diferente: #{result.differences.join(', ')}")
      puts [result.table, result.account_id, result.account&.name, result.erp_source_id, status].join(' | ')
    end
    results.group_by(&:table).each { |table, rows| puts "  #{table}: #{rows.size}" }
    divergent = results.count { |result| result.error || result.differences.any? }
    puts "#{results.size} linhas, #{divergent} com diferença ou erro"
  end

  desc 'Import the Supabase integration_<erp> CSV exports in DIR into account_integrations: rake "supabase:import_integrations[dir]"'
  task :import_integrations, [:dir] => :environment do |_task, args|
    report.call(AccountIntegrations::SupabaseImport.new(dir: args.fetch(:dir), apply: true).perform)
  end

  desc 'Compare the Supabase integration_<erp> CSV exports in DIR with account_integrations: rake "supabase:compare_integrations[dir]"'
  task :compare_integrations, [:dir] => :environment do |_task, args|
    report.call(AccountIntegrations::SupabaseImport.new(dir: args.fetch(:dir)).perform)
  end
end
