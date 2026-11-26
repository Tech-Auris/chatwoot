# Copies the AI setup columns of the Supabase `cliente` table into
# `accounts.settings.ai_config` (see AccountAiConfig), from a CSV export with
# `id` and the AccountAiConfig columns. Blank cells become nil, like the
# Super Admin form saves them. Rerunning replaces the object, so it can be
# rerun until the cut-over.
#
# Dry run unless `apply: true`. Either way it returns, per account, the keys
# that differ in Rails: a run after the import with no differences is the
# Supabase × Rails check.
class Accounts::AiConfigImport
  INTERNAL_ACCOUNTS = SecretarySpecialScenarios::SupabaseImport::INTERNAL_ACCOUNTS

  Result = Struct.new(:account_id, :account, :differences, :error, keyword_init: true)

  def initialize(csv_path:, apply: false)
    @csv_path = csv_path
    @apply = apply
  end

  def perform
    CSV.read(@csv_path, headers: true).map do |line|
      cliente_id = line['id'].to_i
      import(INTERNAL_ACCOUNTS.fetch(cliente_id, cliente_id), Account.cast_ai_config(line.to_h))
    end
  end

  private

  def import(account_id, ai_config)
    account = Account.find_by(id: account_id)
    return Result.new(account_id: account_id, error: 'conta não encontrada') if account.nil?

    account.update!(ai_config: ai_config) if @apply
    stored = account.reload.ai_config
    differences = stored.nil? ? ['sem ai_config'] : ai_config.keys.reject { |key| stored[key] == ai_config[key] }
    Result.new(account_id: account_id, account: account, differences: differences)
  end
end
