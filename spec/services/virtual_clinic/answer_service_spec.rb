require 'rails_helper'

RSpec.describe VirtualClinic::AnswerService do
  let(:account) { create(:account, virtual_clinic_enabled: true, mcp_enabled: true) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:thread) { VirtualClinicThread.create!(account: account, user: user, persona: :secretary) }
  let(:question) { thread.messages.create!(role: :user, status: :done, content: 'Quem você está atendendo agora?') }
  let(:answer) { thread.messages.create!(role: :assistant, status: :pending) }
  let(:mcp) { instance_double(VirtualClinic::McpClient) }
  let(:chat) { double('chat') } # rubocop:disable RSpec/VerifiedDoubles
  let(:reply) { 'Agora estou com **7 pacientes**.' }
  let(:tool_definitions) do
    %w[atendimento_agora funil_resumo buscar_conversas].map do |name|
      { 'name' => name, 'description' => name, 'inputSchema' => { 'type' => 'object', 'properties' => { 'account_id' => {} } } }
    end
  end

  before do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'clinic-key' })
    allow(VirtualClinic::McpClient).to receive(:new).and_return(mcp)
    allow(mcp).to receive(:tools).and_return(tool_definitions)
    context = double('context', chat: chat) # rubocop:disable RSpec/VerifiedDoubles
    allow(Llm::Config).to receive(:with_api_key).with('clinic-key').and_yield(context)
    allow(chat).to receive_messages(with_instructions: chat, with_tools: chat, add_message: chat)
    allow(chat).to receive(:on_tool_call).and_yield(double(name: 'atendimento_agora', arguments: { 'account_id' => 1 })) # rubocop:disable RSpec/VerifiedDoubles
    allow(chat).to receive(:ask).with(question.content) { double(content: reply, input_tokens: 900, output_tokens: 120) } # rubocop:disable RSpec/VerifiedDoubles
  end

  it 'answers with the clinic key and the persona tools only, and pushes the answer to the user' do
    described_class.new(answer).perform

    expect(answer.reload).to have_attributes(status: 'done', content: reply, input_tokens: 900, output_tokens: 120, model: 'gpt-4.1-mini')
    expect(answer.tool_calls).to eq([{ 'name' => 'atendimento_agora', 'arguments' => {} }])
    expect(chat).to have_received(:with_tools) { |*tools| expect(tools.map(&:name)).to eq(%w[atendimento_agora buscar_conversas]) }
    expect(ActionCableBroadcastJob).to have_been_enqueued.with([user.pubsub_token], 'virtual_clinic.message.updated', anything)
  end

  it 'replays the earlier turns as history' do
    question && answer.update!(status: :done, content: 'Olá!')
    follow_up = thread.messages.create!(role: :user, status: :done, content: 'E os follow-ups?')
    next_answer = thread.messages.create!(role: :assistant, status: :pending)
    allow(chat).to receive(:ask).with('E os follow-ups?') { double(content: reply, input_tokens: 1, output_tokens: 1) } # rubocop:disable RSpec/VerifiedDoubles

    described_class.new(next_answer).perform

    expect(next_answer.reload.status).to eq('done')
    expect(follow_up).to be_persisted

    expect(chat).to have_received(:add_message).with(role: :user, content: 'Quem você está atendendo agora?')
    expect(chat).to have_received(:add_message).with(role: :assistant, content: 'Olá!')
  end

  it 'retries once on an empty answer, then gives up with a friendly message' do
    allow(chat).to receive(:ask) { double(content: '', input_tokens: 1, output_tokens: 0) } # rubocop:disable RSpec/VerifiedDoubles

    described_class.new(answer).perform

    expect(chat).to have_received(:ask).twice
    expect(answer.reload).to have_attributes(status: 'failed', content: described_class::EMPTY_ANSWER)
  end

  it 'tells the clinic to check its key when OpenAI refuses it' do
    allow(chat).to receive(:ask).and_raise(RubyLLM::UnauthorizedError.new(nil, 'bad key'))

    described_class.new(answer).perform

    expect(answer.reload).to have_attributes(status: 'failed', content: described_class::KEY_REFUSED)
  end

  it 'fails softly when the MCP is down' do
    allow(mcp).to receive(:tools).and_raise(VirtualClinic::McpClient::Error, 'connection refused')

    described_class.new(answer).perform

    expect(answer.reload).to have_attributes(status: 'failed', content: described_class::DATA_UNAVAILABLE)
  end
end
