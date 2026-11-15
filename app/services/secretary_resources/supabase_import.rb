# Copies the Supabase `resource` table into `secretary_resources`, from a CSV
# export of it (cliente_id, key, resource_type, resource_url, caption, idioma,
# created_at). Each account in the CSV has its resources replaced by the CSV
# rows, so it can be rerun until the cut-over.
#
# Dry run unless `apply: true`. Either way it reports, per account, the CSV rows
# missing in Rails and the Rails rows not in the CSV: a run after the import
# with no differences is the Supabase × Rails check.
class SecretaryResources::SupabaseImport
  # The internal clients whose cliente.id differs from their account id.
  INTERNAL_ACCOUNTS = { 150 => 19, 151 => 66 }.freeze
  COMPARED = %w[key idioma secretary_resource_type_id resource_url caption].freeze

  Result = Struct.new(:account_id, :account, :csv_count, :missing, :extra, :error, keyword_init: true)

  def initialize(csv_path:, apply: false)
    @csv_path = csv_path
    @apply = apply
  end

  def perform
    rows_by_account.map do |account_id, rows|
      account = Account.find_by(id: account_id)
      next Result.new(account_id: account_id, csv_count: rows.size, error: 'conta não encontrada') if account.nil?

      replace(account, rows) if @apply
      compare(account, rows)
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
      'key' => line['key'],
      'idioma' => line['idioma'].presence,
      'secretary_resource_type_id' => line['resource_type'].to_i,
      'resource_url' => line['resource_url'].presence,
      'caption' => line['caption'].presence,
      'created_at' => line['created_at'].presence
    }
  end

  def replace(account, rows)
    SecretaryResource.transaction do
      account.secretary_resources.delete_all
      rows.each { |row| account.secretary_resources.create!(row.compact) }
    end
  end

  def compare(account, rows)
    expected = rows.map { |row| row.values_at(*COMPARED) }.tally
    actual = account.secretary_resources.pluck(*COMPARED.map(&:to_sym)).tally
    Result.new(account_id: account.id, account: account, csv_count: rows.size,
               missing: difference(expected, actual), extra: difference(actual, expected))
  end

  def difference(left, right)
    left.flat_map { |tuple, count| [tuple] * [count - right.fetch(tuple, 0), 0].max }
  end
end
