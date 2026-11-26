# AI setup that came from the Supabase `cliente` table, kept in
# `settings.ai_config` under the same column names and types, so n8n can
# overlay the object onto the legacy `cliente` row as it is:
#
#   prompt_identity                    who the secretary is (name, clinic)
#   bounce_seconds                     seconds the secretary waits for more messages
#                                      (nil takes the n8n default, 0 doesn't wait)
#   flag_audio_on_off                  the secretary answers an audio with an audio
#   chatwoot_id_conversa_alerta        conversation that gets the escalation alert
#   mensagem_de_escala_para_o_usuario  message to the patient on escalation
#   time_padrao_de_escala              team the escalated conversation goes to (a "time")
#
# `phone_alert` is not migrated: no flow uses it.
#
# Every key is always present once the object exists, blank ones as nil.
# An account without the object (no `cliente` row) keeps whatever n8n reads
# from Supabase. Edited in Super Admin only, and hidden from the clinic's
# change history (ActivityLog::INTERNAL_KEYS).
module AccountAiConfig
  extend ActiveSupport::Concern

  AI_CONFIG_FIELDS = {
    'prompt_identity' => :text,
    'bounce_seconds' => :integer,
    'flag_audio_on_off' => :boolean,
    'chatwoot_id_conversa_alerta' => :integer,
    'mensagem_de_escala_para_o_usuario' => :text,
    'time_padrao_de_escala' => :integer
  }.freeze

  def ai_config
    settings&.dig('ai_config')
  end

  def ai_config=(value)
    self.settings = (settings || {}).merge('ai_config' => value && self.class.cast_ai_config(value))
  end

  class_methods do
    def cast_ai_config(value)
      value = value.to_h.stringify_keys
      AI_CONFIG_FIELDS.to_h { |key, type| [key, cast_ai_config_value(type, value[key])] }
    end

    private

    def cast_ai_config_value(type, value)
      return if value.is_a?(String) && value.blank?

      case type
      when :integer then ActiveModel::Type::Integer.new.cast(value)
      when :boolean then ActiveModel::Type::Boolean.new.cast(value)
      else value
      end
    end
  end
end
