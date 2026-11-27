# `settings.ai_config.flag_audio_on_off` can no longer be nil: the secretary
# answers an audio with an audio unless it was turned off (AccountAiConfig).
class DefaultAiConfigAudioFlag < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL.squish
      UPDATE accounts
      SET settings = jsonb_set(settings, '{ai_config,flag_audio_on_off}', 'true')
      WHERE jsonb_typeof(settings -> 'ai_config') = 'object'
        AND jsonb_typeof(settings -> 'ai_config' -> 'flag_audio_on_off') IS DISTINCT FROM 'boolean'
    SQL
  end

  def down; end
end
