# One-shot move of the follow-up setup from the Supabase `cliente` table into
# `accounts.settings.follow_up`, from a CSV export of that table (the columns
# below, by name; any other column is ignored). `fup_minutes` is read both as
# a Postgres array (`{60,480}`) and as JSON (`["60","480"]`).
#
# Dry run unless `apply: true`.
class FollowUp::SupabaseImport
  Row = Struct.new(:account_id, :account, :follow_up, :error, keyword_init: true)

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
    account = Account.find_by(id: account_id)
    row = Row.new(account_id: account_id, account: account, follow_up: follow_up_from(line))
    return row.tap { row.error = 'conta não encontrada' } if account.nil?

    account.follow_up = row.follow_up
    row.error = account.errors.full_messages.to_sentence unless account.valid?
    row
  end

  def follow_up_from(line)
    {
      'steps' => line['fup_minutes'].to_s.scan(/\d+/).map(&:to_i),
      'end_flow' => {
        'enabled' => line['ativa_fluxo_fim_fup'] == 'true',
        'wait_minutes' => line['tempo_espera_minutos_fim_fup'].presence&.to_i,
        'summary_message' => line['mensagem_resumo_fim_fup'].presence,
        'escalation_message' => line['mensagem_escala_para_usuario_fim_fup'].presence
      }
    }
  end

  def save(row)
    return if row.error

    row.account.save!
  rescue ActiveRecord::RecordInvalid => e
    row.error = e.record.errors.full_messages.to_sentence
  end
end
