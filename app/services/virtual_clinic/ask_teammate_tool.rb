# Lets one AI teammate ask another (the manager asks the secretary about
# the front desk now, or the marketing teammate about a campaign, and back). Runs the other persona right away, with the same user
# and token, in a child thread of the asking answer, so the talk is kept for
# audit. The one asked cannot ask anyone back (one level only). The map
# shows the walk to the teammate's desk while the question runs.
class VirtualClinic::AskTeammateTool < RubyLLM::Tool
  TIMEOUT = 45
  NO_ANSWER = 'Não consegui uma resposta agora. Responda com o que você já tem.'.freeze

  def initialize(answer:, asker:, teammate:)
    super()
    @answer = answer
    @asker = asker
    @teammate = teammate
  end

  def name
    "perguntar_#{@teammate.key}"
  end

  def description
    "Pergunta algo para #{@teammate.name} (#{@teammate.role}) e devolve a resposta. " \
      "Use para assuntos da área de #{@teammate.name}: #{@teammate.scope}."
  end

  def params_schema
    { 'type' => 'object', 'properties' => { 'pergunta' => { 'type' => 'string', 'description' => 'A pergunta, completa e direta.' } },
      'required' => ['pergunta'] }
  end

  def execute(pergunta:)
    activity('asking')
    reply = ask(pergunta)
    reply.done? ? reply.content : { error: NO_ANSWER }
  ensure
    activity('done')
  end

  private

  def ask(question)
    thread = VirtualClinicThread.create!(account: @answer.thread.account, user: @answer.thread.user, persona: @teammate.key,
                                         parent_message: @answer)
    thread.messages.create!(role: :user, status: :done, content: question)
    reply = thread.messages.create!(role: :assistant, status: :pending)
    Timeout.timeout(TIMEOUT) { VirtualClinic::AnswerService.new(reply, delegated: true).perform }
    reply.reload
  rescue Timeout::Error
    reply.update!(status: :failed, content: NO_ANSWER)
    reply
  end

  def activity(state)
    thread = @answer.thread
    ActionCableBroadcastJob.perform_later([thread.user.pubsub_token], 'virtual_clinic.activity',
                                          { persona: @asker.key, target: @teammate.key, state: state, account_id: thread.account_id })
  end
end
