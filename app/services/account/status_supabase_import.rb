# One-shot move of the AI secretary status from the Supabase
# `cliente.status_secretaria` into `accounts.status`, from a CSV export of that
# table (the `chatwoot_account_id` and `status_secretaria` columns; any other is
# ignored). A blank status leaves the account as it is, and a suspended account
# stays suspended: blocking the whole account is decided in AurisChat only.
#
# Dry run unless `apply: true`.
class Account::StatusSupabaseImport
  # Ids of the Supabase `status_secretaria` rows.
  SUPABASE_STATUSES = { 1 => :active, 2 => :payment_pending, 3 => :ai_disabled, 4 => :ai_disabled_with_message }.freeze

  Row = Struct.new(:account_id, :account, :status, :error, keyword_init: true)

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
    return if line['status_secretaria'].blank?

    account_id = line['chatwoot_account_id'].to_i
    row = Row.new(account_id: account_id, account: Account.find_by(id: account_id), status: SUPABASE_STATUSES[line['status_secretaria'].to_i])
    row.error = 'conta não encontrada' if row.account.nil?
    row.error ||= "status_secretaria #{line['status_secretaria']} desconhecido" if row.status.nil?
    row.error ||= 'conta suspensa, mantida' if row.account.suspended?
    row
  end

  def save(row)
    return if row.error

    row.account.update!(status: row.status)
  rescue ActiveRecord::RecordInvalid => e
    row.error = e.record.errors.full_messages.to_sentence
  end
end
