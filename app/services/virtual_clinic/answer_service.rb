# Answers one question to an AI teammate: runs the persona's model with its
# MCP tools on the clinic's own OpenAI key, stores the answer (text, tools
# used, charts) and what it spent on the pending assistant message, and
# pushes it to the user. While it runs, the user sees the text as it is
# written (deltas every 150 ms) and which tool is being used.
#
# What it spent covers every OpenAI call of the answer: each round of tools
# (RubyLLM only hands back the last one), the retry of an empty answer and
# the calls of an answer that failed.
class VirtualClinic::AnswerService
  HISTORY_SIZE = 20
  MAX_TOOL_CALLS = 8
  EMPTY_ANSWER = 'Não consegui montar uma resposta agora. Tente perguntar de outro jeito.'.freeze
  KEY_REFUSED = 'A chave da OpenAI da clínica foi recusada. Confira em Configurações → Integrações → OpenAI.'.freeze
  DATA_UNAVAILABLE = 'Não consegui consultar os dados agora. Tente de novo em instantes.'.freeze
  DELTA_INTERVAL = 0.15

  # `delegated`: asked by another AI teammate (AskTeammateTool), so it can't
  # ask anyone itself and nothing is pushed to the user's chat.
  def initialize(answer, delegated: false)
    @answer = answer
    @delegated = delegated
    @thread = answer.thread
    @persona = VirtualClinic::Persona.find!(@thread.persona, account: @thread.account)
    @calls = []
  end

  def perform
    response = ask
    response ||= ask
    return finish(status: :failed, content: EMPTY_ANSWER) if response.nil?

    finish(status: :done, content: response.content)
  rescue RubyLLM::UnauthorizedError, RubyLLM::PaymentRequiredError, RubyLLM::ForbiddenError
    finish(status: :failed, content: KEY_REFUSED)
  rescue VirtualClinic::McpClient::Error, RubyLLM::Error => e
    Rails.logger.warn("[VirtualClinic] answer #{@answer.id} failed: #{e.class} #{e.message}")
    finish(status: :failed, content: DATA_UNAVAILABLE)
  end

  private

  # The model's reply, or nil when it came back empty (gpt-5.1 does that).
  def ask
    @tool_calls = []
    @charts = []
    @streamed = +''
    Llm::Config.with_api_key(VirtualClinicPolicy.openai_api_key(@thread.account)) do |context|
      response = build_chat(context).ask(question.content) { |chunk| stream(chunk) }
      response.content.presence && response
    end
  end

  # Sends the text written so far, at most every DELTA_INTERVAL.
  def stream(chunk)
    return if chunk.content.blank?

    @streamed << chunk.content
    now = monotonic_now
    return if @last_delta && now - @last_delta < DELTA_INTERVAL

    @last_delta = now
    push('virtual_clinic.message.delta', content: @streamed.dup)
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # Straight to the user's socket: deltas must arrive in order and fast.
  def push(event, **data)
    return if @delegated

    ActionCable.server.broadcast(@thread.user.pubsub_token,
                                 { event: event, data: { id: @answer.id, persona: @thread.persona, account_id: @thread.account_id, **data } })
  end

  def build_chat(context)
    chat = context.chat(model: @persona.model)
                  .with_instructions(@persona.instructions(account: @thread.account, user: @thread.user))
                  .with_tools(*tools)
    chat.on_tool_call do |call|
      @tool_calls << { name: call.name, arguments: call.arguments.except('account_id') }
      # What came before a tool call is the model thinking aloud: start over.
      @streamed = +''
      push('virtual_clinic.message.activity', tool: call.name)
    end
    track_usage(chat)
    history.each { |message| chat.add_message(role: message.role.to_sym, content: message.content) }
    chat
  end

  def tools
    client = VirtualClinic::McpClient.new(@thread.user.access_token.token)
    budget = VirtualClinic::ToolBudget.new(MAX_TOOL_CALLS)
    data_tools = client.tools.select { |tool| @persona.tools.include?(tool['name']) }.map do |definition|
      VirtualClinic::McpTool.new(client: client, account_id: @thread.account_id, definition: definition, budget: budget)
    end
    data_tools + teammate_tools + chart_tools
  end

  def chart_tools
    @persona.charts? && !@delegated ? [VirtualClinic::RenderChartTool.new(@charts)] : []
  end

  def teammate_tools
    return [] if @delegated

    @persona.teammates.map { |teammate| VirtualClinic::AskTeammateTool.new(answer: @answer, asker: @persona, teammate: teammate) }
  end

  def question
    @question ||= @thread.messages.user.where(id: ...@answer.id).last
  end

  def history
    @thread.messages.done.where(id: ...question.id).last(HISTORY_SIZE)
  end

  # Each OpenAI call ends in an assistant message with its tokens; tool
  # results end with none.
  def track_usage(chat)
    chat.on_end_message { |message| @calls << message if message.role == :assistant && message.tokens }
  end

  # Priced at the persona's model: OpenAI answers with a dated model name that
  # RubyLLM's price list doesn't know. Nil when the model has no price there.
  def usage
    { model: @persona.model, llm_calls: @calls.size,
      input_tokens: @calls.sum { |call| call.input_tokens.to_i },
      cached_tokens: @calls.sum { |call| call.cached_tokens.to_i },
      output_tokens: @calls.sum { |call| call.output_tokens.to_i },
      cost_usd: @calls.empty? ? 0 : RubyLLM::Cost.aggregate(@calls.map { |call| call.cost(model: @persona.model) }).total }
  end

  def finish(**attributes)
    @answer.update!(tool_calls: @tool_calls || [], attachments: @charts || [], **usage, **attributes)
    return if @delegated

    ActionCableBroadcastJob.perform_later([@thread.user.pubsub_token], 'virtual_clinic.message.updated', @answer.push_event_data)
  end
end
