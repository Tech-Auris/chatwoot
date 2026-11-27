require 'rails_helper'

RSpec.describe VirtualClinic::PilotReport do
  let(:account) { create(:account, name: 'Clínica Sorriso') }
  let(:user) { create(:user, account: account) }
  let(:thread) { VirtualClinicThread.create!(account: account, user: user, persona: :manager) }

  def answer(status:, seconds:, tools: [], tokens: 100, cost: nil)
    created = 1.hour.ago
    thread.messages.create!(role: :assistant, status: status, content: 'x', model: 'gpt-5.1', llm_calls: 2, input_tokens: tokens,
                            cached_tokens: tokens / 2, output_tokens: tokens / 10, cost_usd: cost,
                            tool_calls: tools.map { |name| { name: name, arguments: {} } }, created_at: created, updated_at: created + seconds)
  end

  it 'summarizes questions, failures, answer time, calls, tokens, cost and tools per account, persona and model' do
    asked_clara = answer(status: :done, seconds: 4, tools: %w[funil_resumo agendamentos_resumo], tokens: 1000, cost: 0.01)
    answer(status: :done, seconds: 10, tools: %w[funil_resumo], tokens: 2000, cost: 0.03)
    answer(status: :failed, seconds: 1, cost: 0.002)
    delegated = VirtualClinicThread.create!(account: account, user: user, persona: :secretary, parent_message: asked_clara)
    delegated.messages.create!(role: :assistant, status: :done, content: 'y', model: 'gpt-4.1-mini', cost_usd: 0.004)

    rows = described_class.new(since: 1.day.ago).rows

    # Clara's answer is not a question of its own: it goes into the cost of the question that asked her (0.01 + 0.004).
    expect(rows).to eq([[account.id, 'Clínica Sorriso', 'manager', 'gpt-5.1', 3, 33.3, 4, 10, 2.0, 1033, 517, 103,
                         0.015333, 0.014, 0.03, 0.046, 'funil_resumo agendamentos_resumo']])
  end

  it 'leaves the cost blank for answers from before it was stored' do
    answer(status: :done, seconds: 4)

    expect(described_class.new(since: 1.day.ago).rows.first[12..15]).to eq([nil, nil, nil, nil])
  end
end
