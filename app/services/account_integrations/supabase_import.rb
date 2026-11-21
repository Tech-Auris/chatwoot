# Copies the ERP credentials from the Supabase `integration_<erp>` tables into
# `account_integrations`, from CSV exports named `integration_<erp>.csv` in one
# directory (a missing file is skipped). Each row becomes the `config` of its
# account and ERP, with every column but `cliente_id`, under the same names and
# cast to the type the ERP gives the field (number, json; text otherwise), as
# the Super Admin form saves it. A column the ERP doesn't list as a field, or a
# value that doesn't cast, fails the row instead of being saved unseen: fix the
# ERP's fields in Super Admin and rerun. Rerunning replaces the config, so it
# can be rerun until the cut-over.
#
# VisualASA has one table for two ERPs (7 CIG, 15 Geral): a row goes to the
# account's when it is one of them, else to 7.
#
# Dry run unless `apply: true`. Either way it reports, per row, the keys that
# differ in Rails: a run after the import with no differences is the
# Supabase × Rails check. The CSVs hold credentials: run on the server and
# delete them afterwards.
class AccountIntegrations::SupabaseImport
  INTERNAL_ACCOUNTS = SecretarySpecialScenarios::SupabaseImport::INTERNAL_ACCOUNTS

  TABLES = {
    'googlecalendar' => 1, 'feegow' => 2, 'clinicaagil' => 3, 'saudeagora' => 4, 'medware' => 5, 'clinicorp' => 6,
    'visualasa' => 7, 'medx' => 8, 'amplimed' => 10, 'amigo' => 11, 'gester' => 12, 'klingo' => 13,
    'prontuarioverde' => 14, 'tisaude' => 16, 'asasaude' => 17
  }.freeze
  VISUALASA = [7, 15].freeze
  IGNORED_COLUMNS = %w[cliente_id].freeze

  Result = Struct.new(:table, :account_id, :account, :erp_source_id, :differences, :error, keyword_init: true)

  def initialize(dir:, apply: false)
    @dir = dir
    @apply = apply
  end

  def perform
    TABLES.flat_map do |table, erp_source_id|
      path = File.join(@dir, "integration_#{table}.csv")
      next [] unless File.exist?(path)

      CSV.read(path, headers: true).map { |line| import(table, erp_source_id, line) }
    end
  end

  private

  def import(table, erp_source_id, line)
    account_id = INTERNAL_ACCOUNTS.fetch(line['cliente_id'].to_i, line['cliente_id'].to_i)
    account = Account.find_by(id: account_id)
    result = Result.new(table: table, account_id: account_id, account: account)
    return result.tap { |row| row.error = 'conta não encontrada' } if account.nil?

    result.erp_source_id = erp_source_id(account, erp_source_id)
    config, errors = config(ErpSource.find(result.erp_source_id), line)
    return result.tap { |row| row.error = errors.join('; ') } if errors.any?

    sync(account, result, config)
  end

  def sync(account, result, config)
    save(account, result.erp_source_id, config) if @apply
    result.tap { |row| row.differences = differences(account, row.erp_source_id, config) }
  rescue ActiveRecord::RecordInvalid => e
    result.tap { |row| row.error = e.record.errors.full_messages.to_sentence }
  end

  def erp_source_id(account, erp_source_id)
    return erp_source_id unless erp_source_id == VISUALASA.first

    VISUALASA.include?(account.erp_source_id) ? account.erp_source_id : VISUALASA.first
  end

  # [config, errors], each column cast as the ERP's field of the same key.
  def config(erp_source, line)
    fields = erp_source.fields.index_by { |field| field['key'] }
    errors = []
    config = line.to_h.except(*IGNORED_COLUMNS).to_h do |key, value|
      next [key, errors << "#{key} não é um campo do ERP #{erp_source.name}"] unless fields[key]

      value, error = AccountIntegration.cast(fields[key], value)
      errors << "#{key} #{error}" if error
      [key, value]
    end
    [config, errors]
  end

  def save(account, erp_source_id, config)
    account.account_integrations.find_or_initialize_by(erp_source_id: erp_source_id).update!(config: config)
  end

  def differences(account, erp_source_id, config)
    integration = account.account_integrations.find_by(erp_source_id: erp_source_id)
    return ['sem integração no Rails'] if integration.nil?

    (config.keys | integration.config.keys).reject { |key| config[key] == integration.config[key] }
  end
end
