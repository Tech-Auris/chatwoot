namespace :supabase do
  ai_config_report = lambda do |results|
    results.each do |result|
      status = result.error || (result.differences.empty? ? 'ok' : "diferente: #{result.differences.join(', ')}")
      puts [result.account_id, result.account&.name, status].join(' | ')
    end
    puts "#{results.size} contas, #{results.count { |result| result.error || result.differences.any? }} com diferença ou erro"
  end

  desc 'Import the AI setup columns of a Supabase cliente CSV export into accounts.settings.ai_config: rake "supabase:import_ai_config[csv]"'
  task :import_ai_config, [:csv] => :environment do |_task, args|
    ai_config_report.call(Accounts::AiConfigImport.new(csv_path: args.fetch(:csv), apply: true).perform)
  end

  desc 'Compare the AI setup columns of a Supabase cliente CSV export with accounts.settings.ai_config: rake "supabase:compare_ai_config[csv]"'
  task :compare_ai_config, [:csv] => :environment do |_task, args|
    ai_config_report.call(Accounts::AiConfigImport.new(csv_path: args.fetch(:csv)).perform)
  end
end
