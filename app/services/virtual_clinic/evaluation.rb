# Runs the evaluation questions of a persona (config/virtual_clinic/eval)
# against a real account, with its OpenAI key and the MCP Auris, and prints
# answer, tools used against expected and time. Nothing is kept afterwards.
class VirtualClinic::Evaluation
  def initialize(account:, user:, persona:, output: $stdout)
    @account = account
    @user = user
    @persona = persona
    @output = output
  end

  def run
    thread = VirtualClinicThread.create!(account: @account, user: @user, persona: @persona.key)
    questions.each_with_index { |item, index| ask(thread, item, index + 1) }
  ensure
    thread&.destroy!
  end

  private

  def questions
    YAML.load_file(Rails.root.join("config/virtual_clinic/eval/#{@persona.key}.yml"))
  end

  def ask(thread, item, number)
    thread.messages.destroy_all
    thread.messages.create!(role: :user, status: :done, content: item['question'])
    answer = thread.messages.create!(role: :assistant, status: :pending)
    started = Time.current
    VirtualClinic::AnswerService.new(answer).perform
    answer.reload
    report(item, number, answer, (Time.current - started).round(1))
  end

  def report(item, number, answer, seconds)
    @output.puts "\n#{number}. #{item['question']}  (#{seconds}s, #{answer.status})"
    @output.puts "   esperado: #{tools(item['tools'])}#{" · #{item['note']}" if item['note']}"
    @output.puts "   usou:     #{tools(answer.tool_calls.pluck('name'))}"
    @output.puts answer.content.to_s.gsub(/^/, '   | ')
  end

  def tools(names)
    names.join(', ').presence || 'nenhuma ferramenta'
  end
end
