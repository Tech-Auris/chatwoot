# The ERP/calendar credentials of each account, moved from the 15 Supabase
# `integration_<erp>` tables into one: a row per account and ERP, with that
# table's columns, under the same names, in `config`.
#
# Each ERP lists its fields (`erp_sources.fields`), which build the integration
# form in Super Admin. They start as the Supabase columns, with their types.
# Also adds the Asa Saúde ERP (17), which n8n already uses but Rails didn't have.
class CreateAccountIntegrations < ActiveRecord::Migration[7.1]
  FIELD_DEFAULTS = { 'type' => 'text', 'secret' => false }.freeze
  TOKEN = { 'key' => 'access_token', 'label' => 'Access token', 'secret' => true }.freeze
  VISUALASA = [TOKEN, { 'key' => 'url', 'label' => 'URL' }, { 'key' => 'filial', 'label' => 'Filial' }].freeze
  FIELDS = {
    1 => [{ 'key' => 'calendar_id', 'label' => 'Calendar ID' }],
    2 => [TOKEN, { 'key' => 'local_id', 'label' => 'Local ID', 'type' => 'number' },
          { 'key' => 'unidade_id', 'label' => 'Unidade ID', 'type' => 'number' },
          { 'key' => 'procedimento_id', 'label' => 'Procedimento ID', 'type' => 'number' },
          { 'key' => 'token_overrides', 'label' => 'Token overrides', 'type' => 'json', 'secret' => true }],
    3 => [TOKEN, { 'key' => 'clinica_id', 'label' => 'Clínica ID' }, { 'key' => 'convenio_id', 'label' => 'Convênio ID' }],
    4 => [TOKEN, { 'key' => 'api_url', 'label' => 'API URL' }],
    5 => [{ 'key' => 'identificacao', 'label' => 'Identificação' }, { 'key' => 'senha', 'label' => 'Senha', 'secret' => true },
          { 'key' => 'url', 'label' => 'URL' }],
    6 => [TOKEN, { 'key' => 'codelink', 'label' => 'Codelink' }, { 'key' => 'businessid', 'label' => 'Business ID' }],
    7 => VISUALASA,
    8 => [TOKEN],
    10 => [TOKEN, { 'key' => 'api_url', 'label' => 'API URL' }, { 'key' => 'usuclin', 'label' => 'Usuclin' }],
    11 => [TOKEN, { 'key' => 'place_id', 'label' => 'Place ID', 'type' => 'number' }],
    12 => [{ 'key' => 'identificacao', 'label' => 'Identificação' }, { 'key' => 'senha', 'label' => 'Senha', 'secret' => true },
           { 'key' => 'link', 'label' => 'Link' }],
    13 => [{ 'key' => 'app-token', 'label' => 'App token', 'secret' => true }, { 'key' => 'link', 'label' => 'Link' }],
    14 => [{ 'key' => 'client_id', 'label' => 'Client ID' }, { 'key' => 'client_secret', 'label' => 'Client secret', 'secret' => true },
           { 'key' => 'link', 'label' => 'Link' }],
    15 => VISUALASA,
    16 => [{ 'key' => 'login', 'label' => 'Login' }, { 'key' => 'senha', 'label' => 'Senha', 'secret' => true },
           { 'key' => 'link', 'label' => 'Link' }],
    17 => [{ 'key' => 'token', 'label' => 'Token', 'secret' => true }, { 'key' => 'link', 'label' => 'Link' }]
  }.freeze

  def up
    create_table :account_integrations do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :erp_source, null: false, foreign_key: true
      t.jsonb :config, null: false, default: {}
      t.timestamps
    end
    add_index :account_integrations, %i[account_id erp_source_id], unique: true
    add_column :erp_sources, :fields, :jsonb, null: false, default: []

    now = connection.quote(Time.current)
    execute("INSERT INTO erp_sources (id, name, active, created_at, updated_at) VALUES (17, 'Asa Saúde', true, #{now}, #{now}) " \
            'ON CONFLICT DO NOTHING')
    seed_fields
  end

  def down
    remove_column :erp_sources, :fields
    drop_table :account_integrations
  end

  private

  def seed_fields
    FIELDS.each do |id, fields|
      fields = fields.map { |field| FIELD_DEFAULTS.merge(field) }
      execute("UPDATE erp_sources SET fields = #{connection.quote(fields.to_json)}::jsonb WHERE id = #{id}")
    end
  end
end
