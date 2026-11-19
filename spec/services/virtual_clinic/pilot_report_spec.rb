require 'rails_helper'

RSpec.describe VirtualClinic::PilotReport do
  let(:account) { create(:account, name: 'Clínica Sorriso') }
  let(:user) { create(:user, account: account) }
  let(:thread) { VirtualClinicThread.create!(account: account, user: user, persona: :manager) }

  def answer(status:, seconds:, tools: [], tokens: 100)
    created = 1.hour.ago
    thread.messages.create!(role: :assistant, status: status, content: 'x', input_tokens: tokens, output_tokens: tokens / 10,
                            tool_calls: tools.map { |name| { name: name, arguments: {} } }, created_at: created, updated_at: created + seconds)
  end

  it 'summarizes questions, failures, answer time, tokens and tools per account and persona' do
    answer(status: :done, seconds: 4, tools: %w[funil_resumo agendamentos_resumo], tokens: 1000)
    answer(status: :done, seconds: 10, tools: %w[funil_resumo], tokens: 2000)
    answer(status: :failed, seconds: 1)

    row = described_class.new(since: 1.day.ago).rows.first

    expect(row).to eq([account.id, 'Clínica Sorriso', 'manager', 3, 33.3, 4, 10, 1033, 103, 'funil_resumo agendamentos_resumo'])
  end
end
