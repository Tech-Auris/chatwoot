# Copies the Supabase `confirmacoes` table into `secretary_confirmations`, from
# a CSV export of it (chatwoot_account_id plus the reminder columns). Each
# account in the CSV has its rows replaced by the CSV rows, so it can be rerun
# until the cut-over.
#
# Dry run unless `apply: true`. Either way it reports, per account, the CSV rows
# missing in Rails and the Rails rows not in the CSV: a run after the import
# with no differences is the Supabase × Rails check. "" and NULL compare equal,
# since n8n treats both as "no reminder".
class SecretaryConfirmations::SupabaseImport
  COLUMNS = %w[versao_workflow calendar_id inbox_id unidade_id message_96h message_72h message_48h message message_hj message_2h message_30m].freeze

  Result = Struct.new(:account_id, :account, :csv_count, :missing, :extra, :error, keyword_init: true)

  def initialize(csv_path:, apply: false)
    @csv_path = csv_path
    @apply = apply
  end

  def perform
    rows_by_account.map do |account_id, rows|
      account = Account.find_by(id: account_id)
      next Result.new(account_id: account_id, csv_count: rows.size, error: 'conta não encontrada') if account.nil?

      replace(account, rows) if @apply
      compare(account, rows)
    end
  end

  private

  def rows_by_account
    lines = CSV.read(@csv_path, headers: true).group_by { |line| line['chatwoot_account_id'].to_i }
    lines.transform_values { |account_lines| account_lines.map { |line| line.to_h.slice(*COLUMNS) } }
  end

  def replace(account, rows)
    SecretaryConfirmation.transaction do
      account.secretary_confirmations.delete_all
      rows.each { |row| account.secretary_confirmations.create!(row) }
    end
  end

  def compare(account, rows)
    expected = rows.map { |row| comparable(row.values_at(*COLUMNS)) }.tally
    actual = account.secretary_confirmations.pluck(*COLUMNS.map(&:to_sym)).map { |values| comparable(values) }.tally
    Result.new(account_id: account.id, account: account, csv_count: rows.size,
               missing: difference(expected, actual), extra: difference(actual, expected))
  end

  def comparable(values)
    values.map { |value| value.to_s.presence }
  end

  def difference(left, right)
    left.flat_map { |tuple, count| [tuple] * [count - right.fetch(tuple, 0), 0].max }
  end
end
