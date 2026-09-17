class CreateConversionEventDispatches < ActiveRecord::Migration[7.1]
  # One row per (conversion_event × conversation × provider) attempt to push
  # a conversion downstream. Serves two purposes:
  #   1. Idempotency — the same funnel_stage_reached event on a conversation
  #      must not fire twice at Meta if the operator resolves and reopens.
  #      `event_id` is a stable derivation of (conversation, conversion_event,
  #      provider) and unique per provider.
  #   2. History — the operator (and support) can answer "did the sale on
  #      conversation #123 reach Meta?" by looking at the dispatch row.
  #
  # `payload` is what we sent (already normalized, with hashed PII) so we
  # can retry a `failed` row without re-deriving; `response` is what the
  # provider returned. Both are kept jsonb for flexible inspection.
  def change
    create_table :conversion_event_dispatches do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :conversion_event, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.integer :provider, null: false
      t.integer :status, null: false, default: 0
      t.string :event_id, null: false
      t.jsonb :payload, null: false, default: {}
      t.jsonb :response, null: false, default: {}
      t.integer :attempts, null: false, default: 0
      t.datetime :last_attempted_at
      t.timestamps
    end

    add_index :conversion_event_dispatches, %i[provider event_id], unique: true, name: 'index_dispatches_on_provider_and_event_id'
    add_index :conversion_event_dispatches, %i[account_id status]
    add_index :conversion_event_dispatches, %i[conversion_event_id conversation_id]
  end
end
