require 'rails_helper'

RSpec.describe InboxPrompts::SupabaseImport do
  let(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:other_inbox) { create(:inbox, account: account) }
  let!(:internal_account) { create(:account) }
  let!(:internal_inbox) { create(:inbox, account: internal_account) }
  let(:foreign_inbox) { create(:inbox) }
  let(:csv_path) { Rails.root.join('tmp', "inbox_prompts_import_#{SecureRandom.hex(4)}.csv") }

  before do
    stub_const("#{described_class}::INTERNAL_ACCOUNTS", { 150 => internal_account.id })
    CSV.open(csv_path, 'w') do |csv|
      csv << %w[id created_at cliente_id ai_prompt_system_message inbox_id_arr]
      csv << [1, '2026-01-02 10:00:00+00', account.id, 'Prompt da recepção', "{#{inbox.id},#{other_inbox.id}}"]
      csv << [2, '2026-01-02 10:00:00+00', account.id, 'Repete a recepção', "{#{inbox.id}}"]
      csv << [3, '2026-01-02 10:00:00+00', account.id, 'De outra conta', "{#{foreign_inbox.id}}"]
      csv << [4, '2026-01-02 10:00:00+00', 150, 'Interno', "[#{internal_inbox.id}]"]
      csv << [5, '2026-01-02 10:00:00+00', 999_999, 'Órfão', '{1}']
    end
  end

  after { FileUtils.rm_f(csv_path) }

  def result_for(results, account_id)
    results.find { |result| result.account_id == account_id }
  end

  it 'only reports the differences and conflicts in a dry run' do
    results = described_class.new(csv_path: csv_path).perform

    expect(result_for(results, account.id).missing.size).to eq(1)
    expect(result_for(results, account.id).conflicts).to contain_exactly(
      "inboxes #{inbox.id}: inbox repetida (#{inbox.id})", "inboxes #{foreign_inbox.id}: inbox de outra conta (#{foreign_inbox.id})"
    )
    expect(result_for(results, 999_999).error).to eq('conta não encontrada')
    expect(InboxPrompt.count).to eq(0)
  end

  it "replaces each account's prompts with the valid rows, remapping the internal clients" do
    create(:inbox_prompt, account: account, inbox_ids: [other_inbox.id], ai_prompt_system_message: 'Antigo')

    results = described_class.new(csv_path: csv_path, apply: true).perform

    expect(account.inbox_prompts.sole).to have_attributes(ai_prompt_system_message: 'Prompt da recepção',
                                                          inbox_ids: [inbox.id, other_inbox.id].sort)
    expect(internal_account.inbox_prompts.sole).to have_attributes(ai_prompt_system_message: 'Interno', inbox_ids: [internal_inbox.id])
    expect(results.reject(&:error)).to all(have_attributes(missing: [], extra: []))
  end

  it 'is idempotent and reports a prompt changed in Rails after the import' do
    described_class.new(csv_path: csv_path, apply: true).perform
    described_class.new(csv_path: csv_path, apply: true).perform
    account.inbox_prompts.sole.update!(ai_prompt_system_message: 'Mudou')

    result = result_for(described_class.new(csv_path: csv_path).perform, account.id)

    expect(account.inbox_prompts.count).to eq(1)
    expect(result.missing.size).to eq(1)
    expect(result.extra.size).to eq(1)
  end
end
