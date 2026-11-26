require 'administrate/field/base'

# "Configuração da IA" block of the Super Admin account form: the AI setup
# that came from the Supabase `cliente` table (see AccountAiConfig). Saved by
# AccountsController#merge_ai_config into `settings.ai_config`.
class AccountAiConfigField < Administrate::Field::Base
  def to_s
    value('prompt_identity').to_s.truncate(80)
  end

  def value(key)
    data&.dig(key)
  end
end
