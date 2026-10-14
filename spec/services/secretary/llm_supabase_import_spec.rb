require 'rails_helper'

RSpec.describe Secretary::LlmSupabaseImport do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:csv_path) { Rails.root.join('tmp', "llm_import_#{SecureRandom.hex(4)}.csv") }
  let!(:sonnet) { create(:ai_model, key: 'anthropic_sonnet') }
  let!(:advanced) { create(:ai_model, key: 'openai_advanced') }

  before do
    CSV.open(csv_path, 'w') do |csv|
      csv << %w[id name_institution chatwoot_account_id llm_index]
      csv << [1, 'Auris', account.id, '1']
      csv << [2, 'CER', other_account.id, nil]
      csv << [3, 'Sem conta', 0, '1']
    end
  end

  after { FileUtils.rm_f(csv_path) }

  it 'only reports the plan in a dry run' do
    rows = described_class.new(csv_path: csv_path).perform

    expect(rows.map(&:ai_model)).to eq([sonnet, advanced, sonnet])
    expect(rows.last.error).to eq('conta não encontrada')
    expect(account.reload.account_secretary).to be_nil
  end

  it 'points each account secretary at the model of its index, gpt-5.1 when blank' do
    described_class.new(csv_path: csv_path, apply: true).perform

    expect(account.reload.account_secretary.ai_model).to eq(sonnet)
    expect(other_account.reload.account_secretary.ai_model).to eq(advanced)
  end
end
