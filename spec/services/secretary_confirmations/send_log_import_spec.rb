require 'rails_helper'

RSpec.describe SecretaryConfirmations::SendLogImport do
  let(:account) { create(:account) }
  let(:csv_path) { Rails.root.join('tmp', "secretary_confirmation_send_logs_import_#{SecureRandom.hex(4)}.csv") }

  before do
    CSV.open(csv_path, 'w') do |csv|
      csv << %w[id calendar_id chatwoot_account_id event_id reminder_type sent_at]
      csv << [1, 'agenda@google', account.id, 'ev1', '24h', '2026-11-17 16:30:57.078828+00']
      csv << [2, 'agenda@google', account.id, 'ev1', '2h', '2026-11-17 18:30:00+00']
      csv << [3, 'agenda@google', 999_999, 'ev9', '24h', '2026-11-17 16:30:57+00']
    end
  end

  after { FileUtils.rm_f(csv_path) }

  it 'only counts in a dry run' do
    results = described_class.new(csv_path: csv_path).perform

    expect(results.find { |result| result.account_id == account.id }).to have_attributes(csv_count: 2, rails_count: 0)
    expect(results.find { |result| result.account_id == 999_999 }.error).to eq('conta não encontrada')
  end

  it 'imports the log keeping sent_at, and can rerun over the rows already there' do
    create(:secretary_confirmation_send_log, account: account, calendar_id: 'agenda@google', event_id: 'ev1', reminder_type: '24h')

    2.times { described_class.new(csv_path: csv_path, apply: true).perform }

    expect(account.secretary_confirmation_send_logs.count).to eq(2)
    expect(account.secretary_confirmation_send_logs.find_by(reminder_type: '2h').sent_at).to eq(Time.zone.parse('2026-11-17 18:30:00+00'))
  end
end
