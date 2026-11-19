require 'rails_helper'

RSpec.describe VirtualClinic::McpTool do
  let(:client) { instance_double(VirtualClinic::McpClient) }
  let(:definition) do
    { 'name' => 'funil_resumo', 'description' => 'Funil',
      'inputSchema' => { '$schema' => 'x', 'type' => 'object', 'required' => %w[account_id],
                         'properties' => { 'account_id' => { 'type' => 'number' }, 'desde' => { 'type' => 'string' } } } }
  end
  let(:budget) { VirtualClinic::ToolBudget.new(1) }
  let(:tool) { described_class.new(client: client, account_id: 7, definition: definition, budget: budget) }

  it 'hides the account from the model' do
    expect(tool.name).to eq('funil_resumo')
    expect(tool.params_schema).to eq('type' => 'object', 'required' => [], 'properties' => { 'desde' => { 'type' => 'string' } })
  end

  it 'fills the account in and stops after the budget' do
    allow(client).to receive(:call).and_return('{"leads": 4}')

    expect(tool.call('desde' => '2026-11-01')).to eq('{"leads": 4}')
    expect(client).to have_received(:call).with('funil_resumo', desde: '2026-11-01', account_id: 7)
    expect(tool.call({})).to include(:error)
  end
end
