# Copies columns of the Supabase `cliente` table into the account, from a CSV
# export with `id` and any of the migrated columns: the owner contact
# (IDENTITY_COLUMNS, `accounts` columns) and the AI setup (`settings.ai_config`,
# see AccountAiConfig). Only the columns in the CSV are written, so each group
# can be imported on its own. Blank cells become nil, like the Super Admin form
# saves them. `name_institution` is not imported: the account name stays.
#
# Dry run unless `apply: true`. Either way it returns, per account, the columns
# that differ in Rails: a run after the import with no differences is the
# Supabase × Rails check.
class Accounts::ClienteImport
  INTERNAL_ACCOUNTS = SecretarySpecialScenarios::SupabaseImport::INTERNAL_ACCOUNTS
  IDENTITY_COLUMNS = %w[name_owner phone_contact email_contact].freeze

  Result = Struct.new(:account_id, :account, :differences, :error, keyword_init: true)

  def initialize(csv_path:, apply: false)
    @csv_path = csv_path
    @apply = apply
  end

  def perform
    csv = CSV.read(@csv_path, headers: true)
    @identity_columns = IDENTITY_COLUMNS & csv.headers
    @ai_config_keys = Account::AI_CONFIG_FIELDS.keys & csv.headers
    csv.map do |line|
      cliente_id = line['id'].to_i
      import(INTERNAL_ACCOUNTS.fetch(cliente_id, cliente_id), line.to_h)
    end
  end

  private

  def import(account_id, line)
    account = Account.find_by(id: account_id)
    return Result.new(account_id: account_id, error: 'conta não encontrada') if account.nil?

    identity = line.slice(*@identity_columns).transform_values(&:presence)
    ai_config = Account.cast_ai_config(line).slice(*@ai_config_keys)
    save(account, identity, ai_config) if @apply
    Result.new(account_id: account_id, account: account, differences: differences(account.reload, identity, ai_config))
  end

  def save(account, identity, ai_config)
    account.assign_attributes(identity)
    account.ai_config = (account.ai_config || {}).merge(ai_config) if ai_config.any?
    account.save!
  end

  def differences(account, identity, ai_config)
    stored = account.ai_config || {}
    identity.keys.reject { |column| account[column] == identity[column] } +
      ai_config.keys.reject { |key| stored.key?(key) && stored[key] == ai_config[key] }
  end
end
