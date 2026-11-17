require 'rails_helper'

RSpec.describe SecretaryConfirmations::SupabaseImport do
  let(:account) { create(:account) }
  let(:csv_path) { Rails.root.join('tmp', "secretary_confirmations_import_#{SecureRandom.hex(4)}.csv") }
  let(:columns) do
    %w[id calendar_id chatwoot_account_id message message_48h message_2h message_30m message_hj versao_workflow inbox_id message_72h unidade_id
       message_96h]
  end

  before do
    CSV.open(csv_path, 'w') do |csv|
      csv << columns
      csv << [1, 'agenda@google', account.id, 'Lembrete 24h', '', '', nil, 'Hoje', '5.1', '243', nil, 1, '']
      csv << [2, '', account.id, 'Unidade 2', '', '', nil, nil, '5.1', '243', nil, 2, '']
      csv << [3, 'agenda@google', 999_999, 'Orfã', nil, nil, nil, nil, nil, nil, nil, nil, nil]
    end
  end

  after { FileUtils.rm_f(csv_path) }

  it 'only reports the differences in a dry run' do
    results = described_class.new(csv_path: csv_path).perform

    expect(results.find { |result| result.account_id == account.id }.missing.size).to eq(2)
    expect(results.find { |result| result.account_id == 999_999 }.error).to eq('conta não encontrada')
    expect(SecretaryConfirmation.count).to eq(0)
  end

  it "replaces each account's rows" do
    create(:secretary_confirmation, account: account, message: 'antiga')

    results = described_class.new(csv_path: csv_path, apply: true).perform

    rows = account.secretary_confirmations.pluck(:message, :unidade_id, :inbox_id)
    expect(rows).to contain_exactly(['Lembrete 24h', 1, '243'], ['Unidade 2', 2, '243'])
    expect(account.secretary_confirmations.find_by(unidade_id: 1)).to have_attributes(message_2h: '', message_30m: nil)
    expect(results.reject(&:error)).to all(have_attributes(missing: [], extra: []))
  end

  it 'reports a row changed in Rails after the import' do
    described_class.new(csv_path: csv_path, apply: true).perform
    account.secretary_confirmations.find_by(unidade_id: 2).update!(message: 'Mudou')

    result = described_class.new(csv_path: csv_path).perform.find { |row| row.account_id == account.id }

    expect(result.missing.size).to eq(1)
    expect(result.extra.size).to eq(1)
  end
end
