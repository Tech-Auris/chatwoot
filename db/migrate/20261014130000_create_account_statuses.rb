# The AI secretary status moves from the Supabase `status_secretaria` table
# into the account status itself. Besides `active` and `suspended` (the whole
# account blocked), three statuses keep the team working but tell the n8n
# secretary to stay silent, optionally leaving a private note. This table holds
# the per-status settings the n8n "Pega Status Cliente" flow reads, seeded with
# the rows Supabase has today.
class CreateAccountStatuses < ActiveRecord::Migration[7.1]
  STATUSES = [
    { status: 0, label: 'Ativa', name: 'ATIVO', send_private_message: false },
    { status: 1, label: 'Suspensa', name: 'SUSPENSO', send_private_message: false },
    { status: 2, label: 'Sem pagamento', name: 'SEM_PAGAMENTO', send_private_message: true, message_cooldown_minutes: 60,
      private_message: 'Ainda não identificamos o seu pagamento. ' \
                       'Por favor, entre em contato conosco para que possamos verificar a situação.' },
    { status: 3, label: 'IA desligada', name: 'DESLIGADO_SEM_MENSAGEM', send_private_message: false },
    { status: 4, label: 'IA desligada com mensagem', name: 'DESLIGADO_COM_MENSAGEM', send_private_message: true, message_cooldown_minutes: 60,
      private_message: 'No momento, o serviço encontra-se desativado. ' \
                       'Entre em contato conosco para que possamos verificar e orientar sobre os próximos passos.' }
  ].freeze

  def up
    create_table :account_statuses do |t|
      t.integer :status, null: false
      t.string :label, null: false
      t.string :name, null: false
      t.boolean :send_private_message, null: false, default: false
      t.text :private_message
      t.integer :message_cooldown_minutes
      t.timestamps
    end
    add_index :account_statuses, :status, unique: true

    now = Time.current
    STATUSES.each do |row|
      attrs = { private_message: nil, message_cooldown_minutes: nil, created_at: now, updated_at: now }.merge(row)
      execute("INSERT INTO account_statuses (#{attrs.keys.join(', ')}) VALUES (#{attrs.values.map { |v| connection.quote(v) }.join(', ')})")
    end
  end

  def down
    drop_table :account_statuses
  end
end
