require 'rails_helper'

RSpec.describe FollowUp::SupabaseImport do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:csv_path) { Rails.root.join('tmp', "follow_up_import_#{SecureRandom.hex(4)}.csv") }
  let(:header) do
    %w[id name_institution chatwoot_account_id fup_minutes tempo_espera_minutos_fim_fup mensagem_resumo_fim_fup
       mensagem_escala_para_usuario_fim_fup ativa_fluxo_fim_fup]
  end

  before do
    CSV.open(csv_path, 'w') do |csv|
      csv << header
      csv << [1, 'Auris', account.id, '["60","480"]', 60, 'Resumo: @resumo@', 'Vamos encerrar', 'true']
      csv << [2, 'CER', other_account.id, '{360,720,1560}', 60, nil, nil, 'false']
    end
  end

  after { FileUtils.rm_f(csv_path) }

  it 'only reports the plan in a dry run' do
    rows = described_class.new(csv_path: csv_path).perform

    expect(rows.map { |row| row.follow_up['steps'] }).to eq([[60, 480], [360, 720, 1560]])
    expect(rows.map(&:error)).to all(be_nil)
    expect(account.reload.follow_up).to be_nil
  end

  it 'saves the follow-up setup on each account' do
    described_class.new(csv_path: csv_path, apply: true).perform

    expect(account.reload.follow_up).to eq(
      'steps' => [60, 480],
      'end_flow' => { 'enabled' => true, 'wait_minutes' => 60, 'summary_message' => 'Resumo: @resumo@', 'escalation_message' => 'Vamos encerrar' }
    )
    expect(other_account.reload.follow_up['steps']).to eq([360, 720, 1560])
    expect(other_account.follow_up['end_flow']['enabled']).to be(false)
  end

  it 'saves an empty list when the client has no follow-up' do
    CSV.open(csv_path, 'w') do |csv|
      csv << header
      csv << [3, 'Sem FUP', account.id, nil, 60, nil, nil, 'false']
    end

    described_class.new(csv_path: csv_path, apply: true).perform

    expect(account.reload.follow_up['steps']).to eq([])
  end

  it 'reports, without saving, rows it cannot import' do
    CSV.open(csv_path, 'w') do |csv|
      csv << header
      csv << [4, 'Sumiu', 0, '{60}', 60, nil, nil, 'false']
      csv << [5, 'Demais', account.id, '{1,2,3,4,5,6}', 60, nil, nil, 'false']
    end

    rows = described_class.new(csv_path: csv_path, apply: true).perform

    expect(rows.map(&:error)).to all(be_present)
    expect(account.reload.follow_up).to be_nil
  end
end
