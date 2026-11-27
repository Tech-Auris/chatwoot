# Copies the clinic prompts from Supabase into `account_prompts`, from two CSV
# exports: `cliente` (id, ai_prompt_system_message) for the general prompt and
# `cliente_inbox_prompt` (cliente_id, ai_prompt_system_message, inbox_id_arr;
# ordered by id) for the specific ones, named "Específico 1, 2, ...". Each
# account in the CSVs has its prompts replaced, so it can be rerun until the
# cut-over.
#
# In Supabase a cliente with inbox prompts has no general one (NULL) and its
# inbox prompts cover all its inboxes. Here a specific prompt needs a general
# one, so the first inbox prompt becomes the general prompt (losing its inboxes)
# and the others the specific ones: every inbox keeps the prompt it has today.
#
# An inbox prompt is left out, and listed as a conflict, when it has no prompt
# or no inbox, an inbox from another account, or an inbox an earlier row of the
# account already has. Ops fixes those before the cut-over.
#
# Dry run unless `apply: true`. Either way it reports, per account, the prompts
# missing in Rails and the Rails prompts not in the CSVs: a run after the import
# with no differences is the Supabase × Rails check.
class AccountPrompts::SupabaseImport
  Result = Struct.new(:account_id, :account, :expected_count, :conflicts, :missing, :extra, :error, keyword_init: true)

  def initialize(cliente_csv_path:, inbox_csv_path:, apply: false)
    @cliente_csv_path = cliente_csv_path
    @inbox_csv_path = inbox_csv_path
    @apply = apply
  end

  def perform
    generals = general_prompts
    specifics = inbox_prompts
    (generals.keys | specifics.keys).sort.map do |account_id|
      account = Account.find_by(id: account_id)
      next Result.new(account_id: account_id, error: 'conta não encontrada') if account.nil?

      valid, conflicts = split(account, specifics.fetch(account_id, []))
      prompts = build(generals[account_id], valid)
      replace(account, prompts) if @apply
      compare(account, prompts).tap { |result| result.conflicts = conflicts }
    end
  end

  private

  def general_prompts
    CSV.read(@cliente_csv_path, headers: true).each_with_object({}) do |line, prompts|
      next if line['ai_prompt_system_message'].blank?

      prompts[line['id'].to_i] = line['ai_prompt_system_message']
    end
  end

  def inbox_prompts
    CSV.read(@inbox_csv_path, headers: true).group_by { |line| line['cliente_id'].to_i }.transform_values do |lines|
      lines.map do |line|
        # Postgres array text ({1,2}) or JSON ([1, 2]), depending on the export.
        { 'ai_prompt_system_message' => line['ai_prompt_system_message'], 'inbox_ids' => line['inbox_id_arr'].to_s.scan(/\d+/).map(&:to_i).uniq.sort }
      end
    end
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

  # The general prompt first, then the specific ones, as the rows to save.
  def build(general, specifics)
    specifics = specifics.dup
    general ||= specifics.shift&.fetch('ai_prompt_system_message')
    return [] if general.nil?

    [{ 'name' => 'Geral', 'ai_prompt_system_message' => general, 'inbox_ids' => [] }] +
      specifics.each_with_index.map { |row, index| row.merge('name' => "Específico #{index + 1}") }
  end

  def replace(account, prompts)
    AccountPrompt.transaction do
      account.account_prompts.delete_all
      prompts.each { |prompt| account.account_prompts.create!(prompt) }
    end
  end

  def compare(account, prompts)
    expected = prompts.map { |prompt| prompt.values_at('name', 'ai_prompt_system_message', 'inbox_ids') }.tally
    actual = account.account_prompts.pluck(:name, :ai_prompt_system_message, :inbox_ids).map { |name, text, ids| [name, text, ids.sort] }.tally
    Result.new(account_id: account.id, account: account, expected_count: prompts.size,
               missing: difference(expected, actual), extra: difference(actual, expected))
  end

  def difference(left, right)
    left.flat_map { |tuple, count| [tuple] * [count - right.fetch(tuple, 0), 0].max }
  end
end
