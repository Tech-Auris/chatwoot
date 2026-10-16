# One-shot move of each account's LLM from the Supabase `cliente.llm_index`
# into `account_secretaries.ai_model`, from a CSV export of that table (the
# `chatwoot_account_id` and `llm_index` columns; any other is ignored). A blank
# index means the account ran on the n8n default, index 2 (gpt-5.1).
#
# Dry run unless `apply: true`.
class Secretary::LlmSupabaseImport
  # The index → key map the n8n LLM selector used before AurisChat held the model.
  LEGACY_INDEX_KEYS = %w[openai_mini anthropic_sonnet openai_advanced openai_inference_mini
                         openai_inference_advanced glm_inference_mini glm_inference_advanced].freeze
  DEFAULT_INDEX = 2

  Row = Struct.new(:account_id, :account, :llm_index, :ai_model, :error, keyword_init: true)

  def initialize(csv_path:, apply: false)
    @csv_path = csv_path
    @apply = apply
  end

  def perform
    rows = CSV.read(@csv_path, headers: true).map { |line| build_row(line) }
    rows.each { |row| save(row) } if @apply
    rows
  end

  private

  def build_row(line)
    account_id = line['chatwoot_account_id'].to_i
    index = line['llm_index'].presence&.to_i || DEFAULT_INDEX
    row = Row.new(account_id: account_id, account: Account.find_by(id: account_id), llm_index: index,
                  ai_model: AiModel.find_by(key: LEGACY_INDEX_KEYS[index]))
    row.error = 'conta não encontrada' if row.account.nil?
    row.error ||= "llm_index #{index} sem modelo cadastrado" if row.ai_model.nil?
    row
  end

  def save(row)
    return if row.error

    secretary = row.account.account_secretary || row.account.build_account_secretary
    secretary.update!(ai_model: row.ai_model)
  rescue ActiveRecord::RecordInvalid => e
    row.error = e.record.errors.full_messages.to_sentence
  end
end
