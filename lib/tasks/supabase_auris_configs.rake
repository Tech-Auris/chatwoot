namespace :supabase do
  auris_configs_report = lambda do |problems|
    problems.each { |problem| puts problem }
    puts "#{problems.size} diferenças ou avisos"
  end

  desc 'Import the Supabase configuration and configuration_client CSV exports: rake "supabase:import_configs[config_csv,client_csv]"'
  task :import_configs, [:config_csv, :client_csv] => :environment do |_task, args|
    problems = AurisConfigs::SupabaseImport.new(configuration_csv: args.fetch(:config_csv),
                                                configuration_client_csv: args.fetch(:client_csv), apply: true).perform
    auris_configs_report.call(problems)
  end

  desc 'Compare the Supabase configuration and configuration_client CSV exports with Rails: rake "supabase:compare_configs[config_csv,client_csv]"'
  task :compare_configs, [:config_csv, :client_csv] => :environment do |_task, args|
    problems = AurisConfigs::SupabaseImport.new(configuration_csv: args.fetch(:config_csv),
                                                configuration_client_csv: args.fetch(:client_csv)).perform
    auris_configs_report.call(problems)
  end
end
