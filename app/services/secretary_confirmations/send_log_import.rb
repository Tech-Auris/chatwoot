# Copies the Supabase `confirmacoes_send_log` table into
# `secretary_confirmation_send_logs`, from a CSV export of it (calendar_id,
# chatwoot_account_id, event_id, reminder_type, sent_at). Rows already in Rails
# are skipped, so the full export can be imported first and again, as the
# incremental import, right before the n8n nodes switch.
#
# Dry run unless `apply: true`. Either way it reports, per account, the CSV and
# Rails counts: a run after the import where every Rails count reaches the CSV
# one is the Supabase × Rails check.
class SecretaryConfirmations::SendLogImport
  BATCH_SIZE = 1000

  Result = Struct.new(:account_id, :csv_count, :rails_count, :error, keyword_init: true)

  def initialize(csv_path:, apply: false)
    @csv_path = csv_path
    @apply = apply
  end

  def perform
    rows_by_account.map do |account_id, rows|
      next Result.new(account_id: account_id, csv_count: rows.size, error: 'conta não encontrada') unless Account.exists?(account_id)

      import(rows) if @apply
      Result.new(account_id: account_id, csv_count: rows.size,
                 rails_count: SecretaryConfirmationSendLog.where(account_id: account_id).count)
    end
  end

  private

  def rows_by_account
    CSV.read(@csv_path, headers: true).map { |line| attributes_from(line) }.uniq { |row| row.except(:sent_at) }.group_by { |row| row[:account_id] }
  end

  def attributes_from(line)
    { account_id: line['chatwoot_account_id'].to_i, calendar_id: line['calendar_id'].to_s, event_id: line['event_id'],
      reminder_type: line['reminder_type'], sent_at: line['sent_at'] }
  end

  def import(rows)
    rows.each_slice(BATCH_SIZE) do |batch|
      SecretaryConfirmationSendLog.insert_all(batch, unique_by: :index_secretary_confirmation_send_logs_uniqueness) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
