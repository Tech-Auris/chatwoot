require 'rails_helper'

RSpec.describe Account::StatusSupabaseImport do
  let(:unpaid) { create(:account) }
  let(:off) { create(:account) }
  let(:untouched) { create(:account) }
  let(:suspended) { create(:account, status: :suspended) }
  let(:csv_path) { Rails.root.join('tmp', "status_import_#{SecureRandom.hex(4)}.csv") }

  before do
    CSV.open(csv_path, 'w') do |csv|
      csv << %w[id name_institution chatwoot_account_id status_secretaria]
      csv << [1, 'Sem pagamento', unpaid.id, '2']
      csv << [2, 'Desligada', off.id, '4']
      csv << [3, 'Sem status', untouched.id, nil]
      csv << [4, 'Suspensa', suspended.id, '1']
    end
  end

  after { FileUtils.rm_f(csv_path) }

  it 'only reports the plan in a dry run' do
    rows = described_class.new(csv_path: csv_path).perform

    expect(rows.map(&:status)).to eq(%i[payment_pending ai_disabled_with_message active])
    expect(rows.last.error).to eq('conta suspensa, mantida')
    expect(unpaid.reload).to be_active
  end

  it 'moves each account to the status Supabase had, leaving blank and suspended accounts alone' do
    described_class.new(csv_path: csv_path, apply: true).perform

    expect(unpaid.reload).to be_payment_pending
    expect(off.reload).to be_ai_disabled_with_message
    expect(untouched.reload).to be_active
    expect(suspended.reload).to be_suspended
  end
end
