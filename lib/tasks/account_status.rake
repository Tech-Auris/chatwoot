namespace :accounts do
  desc 'Import each account status from a Supabase cliente CSV (chatwoot_account_id, status_secretaria). Dry run unless APPLY=true'
  task import_status: :environment do
    apply = ENV['APPLY'] == 'true'
    rows = Account::StatusSupabaseImport.new(csv_path: ENV.fetch('CSV'), apply: apply).perform
    rows.each do |row|
      puts [row.account_id, row.account&.name, row.status, row.error ? "ERRO: #{row.error}" : 'ok'].join(' | ')
    end
    failed = rows.count(&:error)
    puts "#{rows.size - failed} contas #{apply ? 'atualizadas' : 'prontas (simulação, nada foi gravado; rode com APPLY=true)'}, #{failed} com erro"
  end
end
