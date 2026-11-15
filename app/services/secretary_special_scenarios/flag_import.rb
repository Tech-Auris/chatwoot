# Copies `cliente.allow_dynamic_special_scenario` from a CSV export of the
# Supabase `cliente` table (id, allow_dynamic_special_scenario) into
# `accounts.settings`. Dry run unless `apply: true`; either way it returns the
# accounts whose value differs from the CSV, so a run after the import with an
# empty list is the Supabase × Rails check.
class SecretarySpecialScenarios::FlagImport
  Result = Struct.new(:account_id, :csv_value, :rails_value, :error, keyword_init: true)

  def initialize(csv_path:, apply: false)
    @csv_path = csv_path
    @apply = apply
  end

  def perform
    CSV.read(@csv_path, headers: true).filter_map do |line|
      cliente_id = line['id'].to_i
      account_id = SecretarySpecialScenarios::SupabaseImport::INTERNAL_ACCOUNTS.fetch(cliente_id, cliente_id)
      value = ActiveModel::Type::Boolean.new.cast(line['allow_dynamic_special_scenario']) || false
      sync(account_id, value)
    end
  end

  private

  def sync(account_id, value)
    account = Account.find_by(id: account_id)
    return Result.new(account_id: account_id, csv_value: value, error: 'conta não encontrada') if account.nil?

    account.update!(allow_dynamic_special_scenario: value) if @apply
    current = account.reload.allow_dynamic_special_scenario || false
    Result.new(account_id: account_id, csv_value: value, rails_value: current) if current != value
  end
end
