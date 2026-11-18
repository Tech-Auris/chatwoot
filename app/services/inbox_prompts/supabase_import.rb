# Copies the Supabase `cliente_inbox_prompt` table into `inbox_prompts`, from a
# CSV export of it (cliente_id, ai_prompt_system_message, inbox_id_arr; ordered
# by id). Each account in the CSV has its prompts replaced by the CSV rows, so
# it can be rerun until the cut-over.
#
# A row is left out, and listed as a conflict, when it has no prompt or no
# inbox, an inbox from another account, or an inbox an earlier row of the
# account already has. Ops fixes those before the cut-over.
#
# Dry run unless `apply: true`. Either way it reports, per account, the CSV rows
# missing in Rails and the Rails rows not in the CSV: a run after the import
# with no differences is the Supabase × Rails check.
class InboxPrompts::SupabaseImport
  INTERNAL_ACCOUNTS = SecretarySpecialScenarios::SupabaseImport::INTERNAL_ACCOUNTS

  Result = Struct.new(:account_id, :account, :csv_count, :conflicts, :missing, :extra, :error, keyword_init: true)

  def initialize(csv_path:, apply: false)
    @csv_path = csv_path
    @apply = apply
  end

  def perform
    rows_by_account.map do |account_id, rows|
      account = Account.find_by(id: account_id)
      next Result.new(account_id: account_id, csv_count: rows.size, error: 'conta não encontrada') if account.nil?

      valid, conflicts = split(account, rows)
      replace(account, valid) if @apply
      compare(account, rows.size, valid).tap { |result| result.conflicts = conflicts }
    end
  end

  private

  def rows_by_account
    CSV.read(@csv_path, headers: true).map { |line| attributes_from(line) }.group_by { |row| row.delete('account_id') }
  end

  def attributes_from(line)
    cliente_id = line['cliente_id'].to_i
    {
      'account_id' => INTERNAL_ACCOUNTS.fetch(cliente_id, cliente_id),
      'ai_prompt_system_message' => line['ai_prompt_system_message'],
      # Postgres array text ({1,2}) or JSON ([1, 2]), depending on the export.
      'inbox_ids' => line['inbox_id_arr'].to_s.scan(/\d+/).map(&:to_i).uniq.sort,
      'created_at' => line['created_at'].presence
    }
  end

  # Returns [valid rows, conflict descriptions]; the first row to claim an inbox keeps it.
  def split(account, rows)
    account_inboxes = account.inboxes.pluck(:id)
    claimed = []
    valid = []
    conflicts = rows.filter_map do |row|
      problem = conflict(row, account_inboxes, claimed)
      next "inboxes #{row['inbox_ids'].join(', ')}: #{problem}" if problem

      claimed.concat(row['inbox_ids'])
      valid << row
      nil
    end
    [valid, conflicts]
  end

  def conflict(row, account_inboxes, claimed)
    return 'prompt vazio' if row['ai_prompt_system_message'].blank?
    return 'sem inbox' if row['inbox_ids'].empty?

    foreign = row['inbox_ids'] - account_inboxes
    return "inbox de outra conta (#{foreign.join(', ')})" if foreign.any?

    repeated = row['inbox_ids'] & claimed
    "inbox repetida (#{repeated.join(', ')})" if repeated.any?
  end

  def replace(account, rows)
    InboxPrompt.transaction do
      account.inbox_prompts.delete_all
      rows.each { |row| account.inbox_prompts.create!(row.compact) }
    end
  end

  def compare(account, csv_count, rows)
    expected = rows.map { |row| row.values_at('ai_prompt_system_message', 'inbox_ids') }.tally
    actual = account.inbox_prompts.pluck(:ai_prompt_system_message, :inbox_ids).map { |text, ids| [text, ids.sort] }.tally
    Result.new(account_id: account.id, account: account, csv_count: csv_count,
               missing: difference(expected, actual), extra: difference(actual, expected))
  end

  def difference(left, right)
    left.flat_map { |tuple, count| [tuple] * [count - right.fetch(tuple, 0), 0].max }
  end
end
