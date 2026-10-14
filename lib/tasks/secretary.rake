namespace :secretary do
  desc 'Move the secretary account webhooks into the Super Admin secretary config. Dry run unless APPLY=true'
  task migrate_webhooks: :environment do
    apply = ENV['APPLY'] == 'true'
    rows = Secretary::WebhookMigration.new(apply: apply).perform
    rows.each do |row|
      target = row.suspended ? 'suspensa → sem secretária' : "caixas: #{row.inbox_ids.presence&.join(', ') || 'nenhuma'}"
      puts [row.webhook.account_id, row.webhook.account.name, row.version_name, target].join(' | ')
    end
    puts "#{rows.size} webhooks — #{apply ? 'migrados' : 'simulação, nada foi gravado (rode com APPLY=true)'}"
  end

  desc 'Rollback: recreate the secretary account webhooks from the Super Admin secretary config'
  task restore_webhooks: :environment do
    webhooks = Secretary::WebhookRestore.new.perform
    webhooks.each { |webhook| puts [webhook.account_id, webhook.name, "caixa: #{webhook.inbox_id || 'todas'}"].join(' | ') }
    puts "#{webhooks.size} webhooks recriados"
  end

  desc 'Import each account LLM from a CSV export of the Supabase cliente table (chatwoot_account_id, llm_index). Dry run unless APPLY=true'
  task import_llm: :environment do
    apply = ENV['APPLY'] == 'true'
    rows = Secretary::LlmSupabaseImport.new(csv_path: ENV.fetch('CSV'), apply: apply).perform
    rows.each do |row|
      puts [row.account_id, row.account&.name, "llm_index #{row.llm_index}", row.ai_model&.name, row.error ? "ERRO: #{row.error}" : 'ok'].join(' | ')
    end
    failed = rows.count(&:error)
    puts "#{rows.size - failed} contas #{apply ? 'importadas' : 'prontas (simulação, nada foi gravado; rode com APPLY=true)'}, #{failed} com erro"
  end
end
