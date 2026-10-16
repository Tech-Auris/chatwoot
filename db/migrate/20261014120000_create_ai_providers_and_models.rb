# The LLM the secretary runs on moves from the Supabase `cliente.llm_index`
# into AurisChat: AI providers and their models are registered in Super Admin
# and each account secretary points at one model. The models the n8n
# secretary already knows are created here with the same keys its LLM
# selector reads (`llm_key`), so accounts can be pointed at them right away.
class CreateAiProvidersAndModels < ActiveRecord::Migration[7.1]
  PROVIDERS = { 'openai' => 'OpenAI', 'anthropic' => 'Anthropic', 'inference' => 'Inference' }.freeze
  MODELS = [
    %w[openai gpt-6.1-sol openai_mini gpt-6.1-sol],
    %w[openai gpt-5.1 openai_advanced gpt-5.1],
    ['anthropic', 'Claude Sonnet 4.5', 'anthropic_sonnet', 'claude-sonnet-4-5-20250929'],
    %w[inference gpt-5.4-mini openai_inference_mini gpt-5.4-mini],
    %w[inference gpt-5.6-sol openai_inference_advanced gpt-5.6-sol],
    %w[inference glm-5.3-flash glm_inference_mini glm-5.3-flash],
    %w[inference glm-5.3 glm_inference_advanced glm-5.3]
  ].freeze

  def up
    create_table :ai_providers do |t|
      t.string :name, null: false
      t.string :key, null: false
      t.timestamps
    end
    add_index :ai_providers, :key, unique: true

    create_table :ai_models do |t|
      t.references :ai_provider, null: false, foreign_key: true
      t.string :name, null: false
      t.string :key, null: false
      t.string :model_id, null: false
      t.integer :status, null: false, default: 0
      t.timestamps
    end
    add_index :ai_models, :key, unique: true

    add_reference :account_secretaries, :ai_model, foreign_key: true

    seed_models
  end

  def down
    remove_reference :account_secretaries, :ai_model, foreign_key: true
    drop_table :ai_models
    drop_table :ai_providers
  end

  private

  def seed_models
    now = Time.current
    provider_ids = PROVIDERS.to_h do |key, name|
      [key, insert_returning_id(:ai_providers, name: name, key: key, created_at: now, updated_at: now)]
    end
    MODELS.each do |provider, name, key, model_id|
      insert_returning_id(:ai_models, ai_provider_id: provider_ids[provider], name: name, key: key, model_id: model_id,
                                      status: 0, created_at: now, updated_at: now)
    end
  end

  def insert_returning_id(table, attrs)
    columns = attrs.keys.join(', ')
    values = attrs.values.map { |value| connection.quote(value) }.join(', ')
    select_value("INSERT INTO #{table} (#{columns}) VALUES (#{values}) RETURNING id")
  end
end
