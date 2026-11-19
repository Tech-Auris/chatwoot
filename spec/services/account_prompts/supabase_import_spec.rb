require 'rails_helper'

RSpec.describe AccountPrompts::SupabaseImport do
  let(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:other_inbox) { create(:inbox, account: account) }
  let!(:third_inbox) { create(:inbox, account: account) }
  let(:general_account) { create(:account) }
  let!(:internal_account) { create(:account) }
  let!(:internal_inbox) { create(:inbox, account: internal_account) }
  let(:foreign_inbox) { create(:inbox) }
  let(:cliente_csv) { Rails.root.join('tmp', "account_prompts_cliente_#{SecureRandom.hex(4)}.csv") }
  let(:inbox_csv) { Rails.root.join('tmp', "account_prompts_inbox_#{SecureRandom.hex(4)}.csv") }

  before do
    stub_const("#{described_class}::INTERNAL_ACCOUNTS", { 150 => internal_account.id })
    CSV.open(cliente_csv, 'w') do |csv|
      csv << %w[id ai_prompt_system_message]
      csv << [account.id, nil]
      csv << [general_account.id, 'Só o geral']
      csv << [150, 'Geral interno']
      csv << [999_999, 'Órfão']
    end
    CSV.open(inbox_csv, 'w') do |csv|
      csv << %w[id created_at cliente_id ai_prompt_system_message inbox_id_arr]
      csv << [1, '2026-01-02 10:00:00+00', account.id, 'Prompt da recepção', "{#{inbox.id}}"]
      csv << [2, '2026-01-02 10:00:00+00', account.id, 'Prompt das unidades', "{#{other_inbox.id},#{third_inbox.id}}"]
      csv << [3, '2026-01-02 10:00:00+00', account.id, 'Repete a recepção', "{#{inbox.id}}"]
      csv << [4, '2026-01-02 10:00:00+00', account.id, 'De outra conta', "{#{foreign_inbox.id}}"]
      csv << [5, '2026-01-02 10:00:00+00', 150, 'Interno', "[#{internal_inbox.id}]"]
    end
  end

  after { FileUtils.rm_f([cliente_csv, inbox_csv]) }

  def result_for(results, account_id)
    results.find { |result| result.account_id == account_id }
  end

  def run(apply: false)
    described_class.new(cliente_csv_path: cliente_csv, inbox_csv_path: inbox_csv, apply: apply).perform
  end

  it 'only reports the differences and conflicts in a dry run' do
    results = run

    expect(result_for(results, account.id).missing.size).to eq(2)
    expect(result_for(results, account.id).conflicts).to contain_exactly(
      "inboxes #{inbox.id}: inbox repetida (#{inbox.id})", "inboxes #{foreign_inbox.id}: inbox de outra conta (#{foreign_inbox.id})"
    )
    expect(result_for(results, 999_999).error).to eq('conta não encontrada')
    expect(AccountPrompt.count).to eq(0)
  end

  it 'turns the first inbox prompt into the general one when the cliente has none' do
    run(apply: true)

    expect(account.account_prompts.ordered.pluck(:name, :ai_prompt_system_message, :inbox_ids)).to eq(
      [['Geral', 'Prompt da recepção', []], ['Específico 1', 'Prompt das unidades', [other_inbox.id, third_inbox.id].sort]]
    )
  end

  it 'keeps the cliente prompt as the general one, remapping the internal clients' do
    run(apply: true)

    expect(general_account.account_prompts.sole).to have_attributes(name: 'Geral', ai_prompt_system_message: 'Só o geral', inbox_ids: [])
    expect(internal_account.account_prompts.ordered.pluck(:name, :ai_prompt_system_message, :inbox_ids)).to eq(
      [['Geral', 'Geral interno', []], ['Específico 1', 'Interno', [internal_inbox.id]]]
    )
  end

  it 'is idempotent and reports a prompt changed in Rails after the import' do
    run(apply: true)
    results = run(apply: true)
    expect(results.reject(&:error)).to all(have_attributes(missing: [], extra: []))

    general_account.account_prompts.sole.update!(ai_prompt_system_message: 'Mudou')
    result = result_for(run, general_account.id)

    expect(general_account.account_prompts.count).to eq(1)
    expect(result.missing.size).to eq(1)
    expect(result.extra.size).to eq(1)
  end
end
