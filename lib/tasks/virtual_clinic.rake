namespace :virtual_clinic do
  # Runs the evaluation questions of a persona against a real account (the
  # clinic's OpenAI key and the MCP Auris) and prints answer, tools and time.
  # The conversation is deleted at the end.
  #   bundle exec rails "virtual_clinic:eval[1,secretary,admin@clinica.com]"
  desc 'Ask a persona its evaluation questions on an account'
  task :eval, %i[account_id persona user_email] => :environment do |_task, args|
    account = Account.find(args[:account_id])
    user = account.users.find_by!(email: args[:user_email])
    persona = VirtualClinic::Persona.find!(args[:persona])
    questions = YAML.load_file(Rails.root.join("config/virtual_clinic/eval/#{persona.key}.yml"))
    thread = VirtualClinicThread.create!(account: account, user: user, persona: persona.key)

    questions.each_with_index do |item, index|
      thread.messages.destroy_all
      thread.messages.create!(role: :user, status: :done, content: item['question'])
      answer = thread.messages.create!(role: :assistant, status: :pending)
      started = Time.current
      VirtualClinic::AnswerService.new(answer).perform
      answer.reload

      puts "\n#{index + 1}. #{item['question']}  (#{(Time.current - started).round(1)}s, #{answer.status})"
      puts "   esperado: #{item['tools'].join(', ').presence || 'nenhuma ferramenta'}#{" · #{item['note']}" if item['note']}"
      puts "   usou:     #{answer.tool_calls.pluck('name').join(', ').presence || 'nenhuma ferramenta'}"
      puts answer.content.to_s.gsub(/^/, '   | ')
    end
  ensure
    thread&.destroy!
  end

  # CSV with the pilot numbers since a date (default: 14 days ago).
  #   bundle exec rails "virtual_clinic:pilot_report[2026-12-01]" > piloto.csv
  desc 'Clínica virtual pilot numbers per account and persona'
  task :pilot_report, %i[since] => :environment do |_task, args|
    since = args[:since].present? ? Time.zone.parse(args[:since]) : 14.days.ago
    puts VirtualClinic::PilotReport.new(since: since).to_csv
  end
end
