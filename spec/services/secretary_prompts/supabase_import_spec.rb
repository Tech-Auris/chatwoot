require 'rails_helper'

RSpec.describe SecretaryPrompts::SupabaseImport do
  let(:csv_path) { Rails.root.join('tmp', "secretary_prompts_import_#{SecureRandom.hex(4)}.csv") }

  before do
    CSV.open(csv_path, 'w') do |csv|
      csv << %w[id core_behavior communication_rules medical_compliance tools_usage]
      csv << [1, "Seja cordial.\nSempre.", 'Mensagens curtas.', 'Sem diagnósticos.', 'Use a agenda.']
      csv << [3, 'Rascunho', nil, nil, nil]
    end
  end

  after { FileUtils.rm_f(csv_path) }

  it 'only reports the differences in a dry run' do
    results = described_class.new(csv_path: csv_path).perform

    expect(results.map(&:differences)).to all(eq(['não existe no Rails']))
    expect(SecretaryPrompt.count).to eq(0)
  end

  it 'imports the rows keeping their ids, and new prompts take the next id' do
    results = described_class.new(csv_path: csv_path, apply: true).perform

    expect(SecretaryPrompt.find(1)).to have_attributes(core_behavior: "Seja cordial.\nSempre.", tools_usage: 'Use a agenda.')
    expect(SecretaryPrompt.find(3).communication_rules).to be_nil
    expect(results.map(&:differences)).to all(be_empty)
    expect(SecretaryPrompt.create!.id).to be > 3
  end

  it 'is idempotent and reports a prompt changed in Rails after the import' do
    2.times { described_class.new(csv_path: csv_path, apply: true).perform }
    SecretaryPrompt.find(1).update!(medical_compliance: 'Mudou')

    results = described_class.new(csv_path: csv_path).perform

    expect(SecretaryPrompt.count).to eq(2)
    expect(results.find { |result| result.id == 1 }.differences).to eq(['medical_compliance'])
  end
end
