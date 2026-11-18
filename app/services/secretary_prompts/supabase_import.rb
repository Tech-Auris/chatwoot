# Copies the Supabase `prompt` table into `secretary_prompts`, from a CSV export
# of it (id, core_behavior, communication_rules, medical_compliance,
# tools_usage), keeping the ids: the flows read row 1.
#
# Dry run unless `apply: true`. Either way it reports, per id, the fields that
# differ between the CSV and Rails: a run after the import with no differences
# is the Supabase × Rails check.
class SecretaryPrompts::SupabaseImport
  FIELDS = %w[core_behavior communication_rules medical_compliance tools_usage].freeze

  Result = Struct.new(:id, :differences, keyword_init: true)

  def initialize(csv_path:, apply: false)
    @csv_path = csv_path
    @apply = apply
  end

  def perform
    rows = CSV.read(@csv_path, headers: true).map { |line| [line['id'].to_i, FIELDS.index_with { |field| line[field] }] }
    import(rows) if @apply
    rows.map { |id, attributes| Result.new(id: id, differences: differences(SecretaryPrompt.find_by(id: id), attributes)) }
  end

  private

  def import(rows)
    SecretaryPrompt.transaction do
      rows.each { |id, attributes| SecretaryPrompt.find_or_initialize_by(id: id).update!(attributes) }
      SecretaryPrompt.connection.reset_pk_sequence!(SecretaryPrompt.table_name)
    end
  end

  def differences(prompt, attributes)
    return ['não existe no Rails'] if prompt.nil?

    FIELDS.reject { |field| prompt[field] == attributes[field] }
  end
end
