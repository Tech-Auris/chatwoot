namespace :supabase do
  cliente_report = lambda do |results|
    results.each do |result|
      status = result.error || (result.differences.empty? ? 'ok' : "diferente: #{result.differences.join(', ')}")
      puts [result.account_id, result.account&.name, status].join(' | ')
    end
    puts "#{results.size} contas, #{results.count { |result| result.error || result.differences.any? }} com diferença ou erro"
  end

  desc 'Import the migrated columns of a Supabase cliente CSV export (owner contact, AI setup) into the accounts: rake "supabase:import_cliente[csv]"'
  task :import_cliente, [:csv] => :environment do |_task, args|
    cliente_report.call(Accounts::ClienteImport.new(csv_path: args.fetch(:csv), apply: true).perform)
  end

  desc 'Compare the migrated columns of a Supabase cliente CSV export with the accounts: rake "supabase:compare_cliente[csv]"'
  task :compare_cliente, [:csv] => :environment do |_task, args|
    cliente_report.call(Accounts::ClienteImport.new(csv_path: args.fetch(:csv)).perform)
  end
end
