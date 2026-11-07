# One-shot move of each clinic's ERP from the Supabase `cliente.integration_type`
# into `accounts.erp_source_id`, from a CSV export of that table (the
# `chatwoot_account_id` and `integration_type` columns; any other is ignored).
# The ids are the same on both sides, so `integration_type` is the ErpSource id.
# A blank `integration_type` leaves the account as it is.
#
# Dry run unless `apply: true`.
class Account::ErpSupabaseImport
  Row = Struct.new(:account_id, :account, :erp_source, :error, keyword_init: true)

  def initialize(csv_path:, apply: false)
    @csv_path = csv_path
    @apply = apply
  end

  def perform
    rows = CSV.read(@csv_path, headers: true).filter_map { |line| build_row(line) }
    rows.each { |row| save(row) } if @apply
    rows
  end

  private

  def build_row(line)
    return if line['integration_type'].blank?

    account_id = line['chatwoot_account_id'].to_i
    row = Row.new(account_id: account_id, account: Account.find_by(id: account_id), erp_source: ErpSource.find_by(id: line['integration_type'].to_i))
    row.error = 'conta não encontrada' if row.account.nil?
    row.error ||= "ERP #{line['integration_type']} não cadastrado" if row.erp_source.nil?
    row
  end

  def save(row)
    return if row.error

    row.account.update!(erp_source: row.erp_source)
  rescue ActiveRecord::RecordInvalid => e
    row.error = e.record.errors.full_messages.to_sentence
  end
end
