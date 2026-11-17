# The appointment reminders one account sends (the 24h `message`, and the
# 96h/72h/48h/today/2h/30m ones), read by the n8n `7. Confirmacoes` flows of
# its `versao_workflow`. Moved from the Supabase `confirmacoes` table, keeping
# its column names; an account can have several rows (one per calendar/unit).
class SecretaryConfirmation < ApplicationRecord
  belongs_to :account

  # Blank templates stay "" (n8n skips the reminder either way), but a blank
  # version must be NULL so the V2 flow, which asks for 'null', finds it.
  before_validation do
    self.versao_workflow = versao_workflow.presence
    self.inbox_id = inbox_id.presence
  end

  # `versions` as n8n asks for them: 'null' matches the rows without a version.
  scope :for_versions, lambda { |versions|
    where(versao_workflow: versions.map { |version| version == 'null' ? nil : version })
  }
end
