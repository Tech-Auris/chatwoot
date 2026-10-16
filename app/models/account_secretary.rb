# Which secretary version serves an account and with which signing secret.
# The inboxes it answers on are flagged on `inboxes.secretary_enabled`; the
# Simulador inbox ignores that flag and uses `simulator_version`, falling back
# to the account's version.
# == Schema Information
#
# Table name: account_secretaries
#
#  id                   :bigint           not null, primary key
#  secret               :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#  ai_model_id          :bigint
#  secretary_version_id :bigint
#  simulator_version_id :bigint
#
# Indexes
#
#  index_account_secretaries_on_account_id            (account_id) UNIQUE
#  index_account_secretaries_on_ai_model_id           (ai_model_id)
#  index_account_secretaries_on_secretary_version_id  (secretary_version_id)
#  index_account_secretaries_on_simulator_version_id  (simulator_version_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (ai_model_id => ai_models.id)
#  fk_rails_...  (secretary_version_id => secretary_versions.id)
#  fk_rails_...  (simulator_version_id => secretary_versions.id)
#
class AccountSecretary < ApplicationRecord
  include WebhookSecretable

  belongs_to :account
  belongs_to :secretary_version, optional: true
  belongs_to :simulator_version, class_name: 'SecretaryVersion', optional: true
  belongs_to :ai_model, optional: true

  validate :secretary_version_selectable, if: -> { secretary_version_id_changed? && secretary_version.present? }
  validate :simulator_version_selectable, if: -> { simulator_version_id_changed? && simulator_version.present? }
  # Checked on change only, so an account picked before LLMs existed keeps
  # saving until its model is filled in.
  validates :ai_model, presence: true, if: -> { secretary_version.present? && (secretary_version_id_changed? || ai_model_id_changed?) }
  validate :ai_model_selectable, if: -> { ai_model_id_changed? && ai_model.present? }

  def version_for(inbox)
    return simulator_version || secretary_version if inbox.channel_type == 'Channel::Simulator'

    secretary_version if inbox.secretary_enabled?
  end

  private

  def secretary_version_selectable
    errors.add(:secretary_version, 'must be an active version') unless secretary_version.active?
  end

  def ai_model_selectable
    errors.add(:ai_model, 'must be an active model') unless ai_model.active?
  end

  def simulator_version_selectable
    errors.add(:simulator_version, 'cannot be a retired version') if simulator_version.retired?
  end
end
