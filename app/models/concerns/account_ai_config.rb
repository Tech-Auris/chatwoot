# AI setup that came from the Supabase `cliente` table, kept in
# `settings.ai_config` under the same column names and types, so n8n can
# overlay the object onto the legacy `cliente` row as it is:
#
#   prompt_identity                    who the secretary is (name, clinic)
#   bounce_seconds                     seconds the secretary waits for more messages
#                                      (nil takes the n8n default, 0 doesn't wait)
#   flag_audio_on_off                  the secretary answers an audio with an audio
#                                      (never nil, true when blank)
#   chatwoot_id_conversa_alerta        conversation that gets the escalation alert
#   mensagem_de_escala_para_o_usuario  message to the patient on escalation
#   time_padrao_de_escala              team the escalated conversation goes to (a "time")
#   calendar_instructions              how the secretary handles the clinic's calendar
#   mensagens_fixas                    list of texts: a conversation whose first message
#                                      contains one of them is left to the team
#
# `phone_alert` is not migrated: no flow uses it.
#
# Every key is always present once the object exists, blank ones as their
# AI_CONFIG_DEFAULTS value or nil. An account created by a sale gets the object
# with the defaults; an account without it (no `cliente` row) keeps whatever
# n8n reads from Supabase. Edited in Super Admin only, and hidden from the clinic's
# change history (ActivityLog::INTERNAL_KEYS).
module AccountAiConfig
  extend ActiveSupport::Concern

  AI_CONFIG_FIELDS = {
    'prompt_identity' => :text,
    'bounce_seconds' => :integer,
    'flag_audio_on_off' => :boolean,
    'chatwoot_id_conversa_alerta' => :integer,
    'mensagem_de_escala_para_o_usuario' => :text,
    'time_padrao_de_escala' => :integer,
    'calendar_instructions' => :text,
    'mensagens_fixas' => :list
  }.freeze

  AI_CONFIG_DEFAULTS = { 'flag_audio_on_off' => true }.freeze

  def ai_config
    settings&.dig('ai_config')
  end

  def ai_config=(value)
    self.settings = (settings || {}).merge('ai_config' => value && self.class.cast_ai_config(value))
  end

  class_methods do
    def cast_ai_config(value)
      value = value.to_h.stringify_keys
      AI_CONFIG_FIELDS.to_h do |key, type|
        cast = cast_ai_config_value(type, value[key])
        [key, cast.nil? ? AI_CONFIG_DEFAULTS[key] : cast]
      end
    end

    private

    def cast_ai_config_value(type, value)
      return cast_ai_config_list(value) if type == :list
      return if value.is_a?(String) && value.blank?

      case type
      when :integer then ActiveModel::Type::Integer.new.cast(value)
      when :boolean then ActiveModel::Type::Boolean.new.cast(value)
      else value
      end
    end

    # An array, or the text of one from a CSV export: JSON (`["a","b"]`) or a
    # Postgres array (`{"a","b"}`). Blank items are dropped; nil when empty.
    def cast_ai_config_list(value)
      value = JSON.parse(value) if value.is_a?(String) && value.start_with?('[')
      value = PG::TextDecoder::Array.new.decode(value) if value.is_a?(String) && value.start_with?('{')
      Array.wrap(value).compact_blank.presence
    end
  end
end
