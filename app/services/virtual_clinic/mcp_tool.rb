# One MCP Auris tool exposed to RubyLLM. The account is filled in here and
# hidden from the model, so it can never ask about another clinic.
class VirtualClinic::McpTool < RubyLLM::Tool
  def initialize(client:, account_id:, definition:, budget:)
    super()
    @client = client
    @account_id = account_id
    @definition = definition
    @budget = budget
  end

  def name
    @definition['name']
  end

  def description
    @definition['description']
  end

  def params_schema
    schema = @definition['inputSchema'].deep_dup.except('$schema')
    schema['properties']&.delete('account_id')
    schema['required']&.delete('account_id')
    schema
  end

  def execute(**arguments)
    return { error: 'Limite de consultas desta resposta atingido. Responda com o que você já tem.' } unless @budget.spend

    @client.call(name, arguments.merge(account_id: @account_id))
  end
end
