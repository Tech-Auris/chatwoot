# Talks to the MCP Auris (stateless Streamable HTTP, JSON responses) with the
# user's own access token, so the AI sees exactly what the user sees.
class VirtualClinic::McpClient
  class Error < StandardError; end

  TIMEOUT = 30

  def initialize(token)
    @token = token
  end

  def tools
    rpc('tools/list')['tools']
  end

  # The tool output as text, or `{ error: }` when the tool itself failed.
  def call(name, arguments)
    result = rpc('tools/call', name: name, arguments: arguments)
    text = Array(result['content']).filter_map { |part| part['text'] }.join("\n")
    result['isError'] ? { error: text } : text
  end

  private

  def rpc(method, params = {})
    response = HTTParty.post(url, body: { jsonrpc: '2.0', id: 1, method: method, params: params }.to_json, headers: headers,
                                  timeout: TIMEOUT)
    body = JSON.parse(response.body)
    raise Error, body.dig('error', 'message') || "MCP #{response.code}" if body['error'] || !response.success?

    body['result']
  rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED => e
    raise Error, e.message
  end

  def url
    ENV.fetch('AURIS_MCP_URL', 'https://mcp.auris.ia.br/mcp')
  end

  def headers
    { 'Authorization' => "Bearer #{@token}", 'Content-Type' => 'application/json', 'Accept' => 'application/json, text/event-stream' }
  end
end
