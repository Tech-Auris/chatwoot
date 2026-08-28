require 'rails_helper'

RSpec.describe Funnel::MoveConversationService do
  let(:account) { create(:account, funnel_enabled: true) }
  let(:user) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let!(:stage) { create(:funnel_stage, name: 'Em Qualificação') }

  def move(**)
    described_class.new(account: account, conversation_display_id: conversation.display_id, user: user, **).perform
  end

  # The kanban has always moved by name; the conversation header points at the
  # id, which survives a stage being renamed mid-flight.
  it 'moves the conversation by stage id' do
    result = move(target_stage_id: stage.id)

    expect(conversation.reload.funnel_stage).to eq(stage)
    expect(result.new_stage).to eq('Em Qualificação')
  end

  it 'still moves the conversation by stage name' do
    move(target_stage_name: 'Em Qualificação')

    expect(conversation.reload.funnel_stage).to eq(stage)
  end

  it 'prefers the id when both are given' do
    other = create(:funnel_stage, name: 'Agendado')

    move(target_stage_id: other.id, target_stage_name: 'Em Qualificação')

    expect(conversation.reload.funnel_stage).to eq(other)
  end

  it 'refuses a move with no destination at all' do
    expect { move }.to raise_error(ArgumentError, /etapa de destino/)
  end

  it 'refuses an id that is not an active stage' do
    inactive = create(:funnel_stage, name: 'Desativada', active: false)

    expect { move(target_stage_id: inactive.id) }.to raise_error(ArgumentError, /is not active/)
  end

  # A stage that demands a reason must not be reachable without one, whichever
  # handle the caller used.
  it 'refuses a stage that requires a loss reason when none is given' do
    lost = create(:funnel_stage, name: 'Perdido', requires_loss_reason: true)

    expect { move(target_stage_id: lost.id) }.to raise_error(ArgumentError, /requires a loss_reason_id/)
  end

  it 'accepts the stage that requires a reason once the reason comes along' do
    lost = create(:funnel_stage, name: 'Perdido', requires_loss_reason: true)
    reason = create(:loss_reason)

    move(target_stage_id: lost.id, loss_reason_id: reason.id)

    expect(conversation.reload.funnel_stage).to eq(lost)
  end
end
