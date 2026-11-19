# Answers one question to an AI teammate: runs the persona's model with its
# MCP tools on the clinic's own OpenAI key, stores the answer (text, tools
# used, tokens) on the pending assistant message and pushes it to the user.
class VirtualClinic::AnswerService
  HISTORY_SIZE = 20
  MAX_TOOL_CALLS = 8
  EMPTY_ANSWER = 'Não consegui montar uma resposta agora. Tente perguntar de outro jeito.'.freeze
  KEY_REFUSED = 'A chave da OpenAI da clínica foi recusada. Confira em Configurações → Integrações → OpenAI.'.freeze
  DATA_UNAVAILABLE = 'Não consegui consultar os dados agora. Tente de novo em instantes.'.freeze

  def initialize(answer)
    @answer = answer
    @thread = answer.thread
    @persona = VirtualClinic::Persona.find!(@thread.persona)
  end

  def perform
    response = ask
    response ||= ask
    return finish(status: :failed, content: EMPTY_ANSWER) if response.nil?

    finish(status: :done, content: response.content, model: @persona.model,
           input_tokens: response.input_tokens, output_tokens: response.output_tokens)
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
    Llm::Config.with_api_key(VirtualClinicPolicy.openai_api_key(@thread.account)) do |context|
      response = build_chat(context).ask(question.content)
      response.content.presence && response
    end
  end

  def build_chat(context)
    chat = context.chat(model: @persona.model)
                  .with_instructions(@persona.instructions(account: @thread.account, user: @thread.user))
                  .with_tools(*tools)
    chat.on_tool_call { |call| @tool_calls << { name: call.name, arguments: call.arguments.except('account_id') } }
    history.each { |message| chat.add_message(role: message.role.to_sym, content: message.content) }
    chat
  end

  def tools
    client = VirtualClinic::McpClient.new(@thread.user.access_token.token)
    budget = VirtualClinic::ToolBudget.new(MAX_TOOL_CALLS)
    client.tools.select { |tool| @persona.tools.include?(tool['name']) }.map do |definition|
      VirtualClinic::McpTool.new(client: client, account_id: @thread.account_id, definition: definition, budget: budget)
    end
  end

  def question
    @question ||= @thread.messages.user.where(id: ...@answer.id).last
  end

  def history
    @thread.messages.done.where(id: ...question.id).last(HISTORY_SIZE)
  end

  def finish(**attributes)
    @answer.update!(tool_calls: @tool_calls || [], **attributes)
    ActionCableBroadcastJob.perform_later([@thread.user.pubsub_token], 'virtual_clinic.message.updated', @answer.push_event_data)
  end
end
