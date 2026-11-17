namespace :follow_up do
  desc 'Import the follow-up setup from a CSV export of the Supabase cliente table. Dry run unless APPLY=true'
  task import: :environment do
    apply = ENV['APPLY'] == 'true'
    rows = FollowUp::SupabaseImport.new(csv_path: ENV.fetch('CSV'), apply: apply).perform
    rows.each do |row|
      end_flow = row.follow_up['end_flow']
      closing = end_flow['enabled'] ? "encerramento após #{end_flow['wait_minutes']} min" : 'sem encerramento'
      puts [row.account_id, row.account&.name, row.follow_up['steps'].join(', ').presence || 'sem FUP', closing,
            row.error ? "ERRO: #{row.error}" : 'ok'].join(' | ')
    end
    failed = rows.count(&:error)
    puts "#{rows.size - failed} contas #{apply ? 'importadas' : 'prontas (simulação, nada foi gravado; rode com APPLY=true)'}, #{failed} com erro"
  end

  desc 'Install the missing kit follow-up templates (e.g. auris_fup_fim) on every WhatsApp Cloud number'
  task install_templates: :environment do
    Channel::Whatsapp.where(provider: 'whatsapp_cloud').find_each do |channel|
      failures = Whatsapp::InstallFollowUpTemplatesJob.perform_now(channel)
      puts [channel.account_id, channel.phone_number, failures.map { |name, error| "#{name}: #{error}" }.join(' · ').presence || 'ok'].join(' | ')
    rescue StandardError => e
      puts [channel.account_id, channel.phone_number, "ERRO: #{e.message}"].join(' | ')
    end
  end
end
