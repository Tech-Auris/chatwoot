require 'rails_helper'

RSpec.describe VirtualClinic::McpClient do
  let(:client) { described_class.new('user-token') }
  let(:url) { 'https://mcp.auris.ia.br/mcp' }

  around { |example| with_modified_env(AURIS_MCP_URL: url) { example.run } }

  def stub_rpc(result)
    stub_request(:post, url).with(headers: { 'Authorization' => 'Bearer user-token' })
                            .to_return(status: 200, body: { jsonrpc: '2.0', id: 1, result: result }.to_json,
                                       headers: { 'Content-Type' => 'application/json' })
  end

  it 'lists the tools with the user token' do
    stub_rpc(tools: [{ name: 'funil_resumo' }])

    expect(client.tools).to eq([{ 'name' => 'funil_resumo' }])
  end

  it 'returns the tool text, or an error the model can read' do
    stub_rpc(content: [{ type: 'text', text: '{"leads": 4}' }])
    expect(client.call('funil_resumo', account_id: 1)).to eq('{"leads": 4}')

    stub_rpc(content: [{ type: 'text', text: 'Sem acesso à conta 9.' }], isError: true)
    expect(client.call('funil_resumo', account_id: 9)).to eq(error: 'Sem acesso à conta 9.')
  end

  it 'raises when the MCP refuses the request' do
    stub_request(:post, url).to_return(status: 401, body: { jsonrpc: '2.0', error: { message: 'Unauthorized' } }.to_json)

    expect { client.tools }.to raise_error(described_class::Error, 'Unauthorized')
  end
end
