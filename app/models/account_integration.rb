# The credentials an account uses to reach its ERP (or calendar), moved from the
# Supabase `integration_<erp>` tables and edited in Super Admin. `config` keeps
# that table's columns under the same names (Klingo's `app-token` included), so
# the n8n nodes that replaced the Supabase ones return the same keys.
#
# An account may keep rows for several ERPs; the one that counts is the row of
# the account's `erp_source`. n8n reads it live from Postgres on every call:
#
#   select x.* from account_integrations ai,
#     jsonb_to_record(ai.config) as x(access_token text, local_id bigint, ...)
#   where ai.account_id = $1 and ai.erp_source_id = 2
#
# Plain text, as in Supabase today; encryption comes with the V2 story.
class AccountIntegration < ApplicationRecord
  include Auditable

  # The Supabase columns of each ERP, keyed by ErpSource id: the keys a new
  # integration starts with. Prodoctor (9) uses a fixed n8n credential.
  FIELDS = {
    1 => %w[calendar_id],
    2 => %w[access_token local_id unidade_id procedimento_id token_overrides],
    3 => %w[access_token clinica_id convenio_id],
    4 => %w[access_token api_url],
    5 => %w[identificacao senha url],
    6 => %w[access_token codelink businessid],
    7 => %w[access_token url filial],
    8 => %w[access_token],
    10 => %w[access_token api_url usuclin],
    11 => %w[access_token place_id],
    12 => %w[identificacao senha link],
    13 => %w[app-token link],
    14 => %w[client_id client_secret link],
    15 => %w[access_token url filial],
    16 => %w[login senha link],
    17 => %w[token link]
  }.freeze

  SECRET_KEYS = %w[access_token token senha client_secret app-token token_overrides].freeze

  belongs_to :account
  belongs_to :erp_source

  validates :erp_source_id, uniqueness: { scope: :account_id }
  validate :config_json_is_an_object

  # Secret values never reach the change history, only the fact that `config` changed.
  auditable filtered: %i[config], label: ->(integration) { integration.erp_source&.name }

  def self.template_for(erp_source_id)
    FIELDS.fetch(erp_source_id.to_i, []).index_with(nil)
  end

  # `config` as the JSON the Super Admin form edits.
  def config_json
    @config_json || JSON.pretty_generate(config)
  end

  def config_json=(text)
    @config_json = text
    parsed = JSON.parse(text)
    self.config = parsed if parsed.is_a?(Hash)
  rescue JSON::ParserError
    nil
  end

  # `config` with each secret cut down to its last 4 characters (`••••1234`).
  def masked_config
    config.to_h { |key, value| [key, SECRET_KEYS.include?(key) && value.present? ? mask(value) : value] }
  end

  def active?
    account.erp_source_id == erp_source_id
  end

  private

  def mask(value)
    value.is_a?(String) && value.length > 8 ? "••••#{value.last(4)}" : '••••'
  end

  def config_json_is_an_object
    return if @config_json.nil?

    parsed = JSON.parse(@config_json)
    errors.add(:config_json, 'precisa ser um objeto JSON ({ "chave": "valor" })') unless parsed.is_a?(Hash)
  rescue JSON::ParserError => e
    errors.add(:config_json, "não é um JSON válido: #{e.message.truncate(120)}")
  end
end
