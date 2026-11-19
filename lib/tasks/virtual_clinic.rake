namespace :virtual_clinic do
  # See VirtualClinic::Evaluation.
  #   bundle exec rails "virtual_clinic:eval[1,secretary,admin@clinica.com]"
  desc 'Ask a persona its evaluation questions on an account'
  task :eval, %i[account_id persona user_email] => :environment do |_task, args|
    account = Account.find(args[:account_id])
    VirtualClinic::Evaluation.new(account: account, user: account.users.find_by!(email: args[:user_email]),
                                  persona: VirtualClinic::Persona.find!(args[:persona])).run
  end

  # Uploads the approved LimeZu selection to private storage (production).
  # The pack never goes into git: the repository is public.
  #   bundle exec rails "virtual_clinic:upload_assets[/path/to/clinica-virtual-selecao]"
  desc 'Upload the Clínica virtual art to private storage'
  task :upload_assets, %i[dir] => :environment do |_task, args|
    VirtualClinic::AssetStore.upload(args.fetch(:dir))
    puts "Uploaded #{ActiveStorage::Blob.where('key LIKE ?', "#{VirtualClinic::AssetStore::KEY_PREFIX}%").count} files"
  end

  # CSV with the pilot numbers since a date (default: 14 days ago).
  #   bundle exec rails "virtual_clinic:pilot_report[2026-12-01]" > piloto.csv
  desc 'Clínica virtual pilot numbers per account and persona'
  task :pilot_report, %i[since] => :environment do |_task, args|
    since = args[:since].present? ? Time.zone.parse(args[:since]) : 14.days.ago
    puts VirtualClinic::PilotReport.new(since: since).to_csv
  end
end
