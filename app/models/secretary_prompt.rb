# The base blocks of the secretary prompt, the same for every account. Moved
# from the Supabase `prompt` table (ids preserved) and edited in Super Admin.
#
# The flows only read row 1, straight from Postgres: `Atualiza Caches Supabase`
# copies it into the Redis key `cache_supabase_prompt` (read by Secretária v3.3
# and SDR) every hour, and Secretária v2.2 reads it live.
# == Schema Information
#
# Table name: secretary_prompts
#
#  id                  :bigint           not null, primary key
#  communication_rules :text
#  core_behavior       :text
#  medical_compliance  :text
#  tools_usage         :text
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
class SecretaryPrompt < ApplicationRecord
  # The base blocks can run past the 20k-character default of ApplicationRecord.
  validates :core_behavior, :communication_rules, :medical_compliance, :tools_usage,
            length: { maximum: AccountPrompt::PROMPT_MAX_LENGTH }
end
