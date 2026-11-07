require 'rails_helper'

RSpec.describe Account::ErpSupabaseImport do
  let(:feegow) { create(:erp_source, id: 2, name: 'Feegow') }
  let(:clinic) { create(:account) }
  let(:untouched) { create(:account) }
  let(:csv_path) { Rails.root.join('tmp', "erp_import_#{SecureRandom.hex(4)}.csv") }

  before do
    CSV.open(csv_path, 'w') do |csv|
      csv << %w[id name_institution chatwoot_account_id integration_type]
      csv << [1, 'Clínica', clinic.id, feegow.id]
      csv << [2, 'Sem ERP', untouched.id, nil]
      csv << [3, 'Conta apagada', 999_999, feegow.id]
      csv << [4, 'ERP desconhecido', untouched.id, 77]
    end
  end

  after { FileUtils.rm_f(csv_path) }

  it 'only reports the plan in a dry run' do
    rows = described_class.new(csv_path: csv_path).perform

    expect(rows.map { |row| [row.account_id, row.erp_source&.name, row.error] })
      .to eq([[clinic.id, 'Feegow', nil], [999_999, 'Feegow', 'conta não encontrada'], [untouched.id, nil, 'ERP 77 não cadastrado']])
    expect(clinic.reload.erp_source).to be_nil
  end

  it 'gives each account the ERP Supabase had, skipping blank and invalid rows' do
    described_class.new(csv_path: csv_path, apply: true).perform

    expect(clinic.reload.erp_source).to eq(feegow)
    expect(untouched.reload.erp_source).to be_nil
  end
end
