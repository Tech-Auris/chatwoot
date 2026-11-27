# Copies the Supabase `configuration` and `configuration_client` tables into
# `auris_configs` and `account_auris_configs`, keeping the ids (n8n caches
# them and writes the checkpoint by id), from CSV exports of both (all
# columns). The account values are replaced by the CSV rows, so it
# can be rerun until the cut-over. A key repeated for the same client in
# Supabase keeps the row with the highest id, the one written last.
#
# Dry run unless `apply: true`. Either way it returns what doesn't match
# between the CSVs and Rails (plus the repeated keys): an empty list after the
# import is the Supabase × Rails check.
class AurisConfigs::SupabaseImport
  CONFIG_COLUMNS = %w[config_key value_type default_value description].freeze

  def initialize(configuration_csv:, configuration_client_csv:, apply: false)
    @configuration_csv = configuration_csv
    @configuration_client_csv = configuration_client_csv
    @apply = apply
    @problems = []
  end

  def perform
    configs = read_configs
    values = read_values(configs)
    import(configs, values) if @apply
    compare_configs(configs)
    compare_values(values)
    @problems
  end

  private

  def read_configs
    CSV.read(@configuration_csv, headers: true).to_h do |line|
      [line['id'].to_i, CONFIG_COLUMNS.index_with { |column| line[column] }]
    end
  end

  # { [account_id, config_id] => [id, value] }, skipping rows Rails can't hold.
  def read_values(configs)
    rows = CSV.read(@configuration_client_csv, headers: true).sort_by { |line| line['id'].to_i }
    account_ids = Account.where(id: rows.map { |line| line['client_id'].to_i }).pluck(:id).to_set
    rows.each_with_object({}) do |line, values|
      key = [line['client_id'].to_i, line['configuration_id'].to_i]
      problem = row_problem(line, key, account_ids, configs)
      next @problems << problem if problem

      warn_repeated(key, line, configs) if values.key?(key)
      values[key] = [line['id'].to_i, line['value']]
    end
  end

  def warn_repeated(key, line, configs)
    @problems << "conta #{key.first}, #{configs[key.last]['config_key']} repetida no Supabase: fica a linha #{line['id']}"
  end

  def row_problem(line, key, account_ids, configs)
    return "linha #{line['id']}: conta #{key.first} não encontrada" unless account_ids.include?(key.first)

    "linha #{line['id']}: configuração #{key.last} não está no CSV" unless configs.key?(key.last)
  end

  def import(configs, values)
    AurisConfig.transaction do
      configs.each { |id, attributes| AurisConfig.find_or_initialize_by(id: id).update!(attributes) }
      AurisConfig.connection.reset_pk_sequence!(AurisConfig.table_name)
      AccountAurisConfig.delete_all
      values.each do |(account_id, config_id), (id, value)|
        AccountAurisConfig.create!(id: id, account_id: account_id, auris_config_id: config_id, value: value)
      end
      AccountAurisConfig.connection.reset_pk_sequence!(AccountAurisConfig.table_name)
    end
  end

  def compare_configs(configs)
    stored = AurisConfig.all.index_by(&:id)
    configs.each do |id, attributes|
      config = stored[id]
      next @problems << "configuração #{id} (#{attributes['config_key']}) falta no Rails" if config.nil?

      different = CONFIG_COLUMNS.reject { |column| config[column] == attributes[column] }
      @problems << "configuração #{id} (#{attributes['config_key']}) diferente: #{different.join(', ')}" if different.any?
    end
  end

  def compare_values(values)
    stored = AccountAurisConfig.pluck(:account_id, :auris_config_id, :id, :value).to_h do |account_id, config_id, id, value|
      [[account_id, config_id], [id, value]]
    end
    (values.keys | stored.keys).sort.each do |key|
      label = "conta #{key.first}, configuração #{key.last}"
      if !stored.key?(key) then @problems << "#{label}: falta no Rails"
      elsif !values.key?(key) then @problems << "#{label}: só no Rails"
      elsif stored[key] != values[key] then @problems << "#{label}: valor ou id diferente"
      end
    end
  end
end
