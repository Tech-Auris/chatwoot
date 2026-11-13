# One row per change to an audited record (see Auditable) or per sign in /
# sign out: who did it, from where, and the before → after of each field.
# Read by the account admin in Settings › Change history.
#
# `audited_changes` maps each field to [before, after]. Sensitive fields keep
# the key but never the value: both sides are FILTERED.
# == Schema Information
#
# Table name: activity_logs
#
#  id              :bigint           not null, primary key
#  action          :string           not null
#  actor_label     :string
#  actor_type      :string           not null
#  auditable_label :string
#  auditable_type  :string           not null
#  audited_changes :jsonb            not null
#  ip_address      :string
#  source          :string           not null
#  created_at      :datetime         not null
#  account_id      :bigint           not null
#  actor_id        :bigint
#  auditable_id    :bigint
#  request_id      :string
#
# Indexes
#
#  index_activity_logs_on_account_id_and_created_at        (account_id,created_at)
#  index_activity_logs_on_actor_type_and_actor_id          (actor_type,actor_id)
#  index_activity_logs_on_auditable_type_and_auditable_id  (auditable_type,auditable_id)
#
class ActivityLog < ApplicationRecord
  FILTERED = '[FILTERED]'.freeze
  ACTIONS = %w[create update destroy merge sign_in sign_out].freeze
  SOURCES = %w[dashboard api job super_admin login].freeze
  SENSITIVE_KEY = /(\A|_)(password|secret|token|api_key|private_key|key|credentials?)\z/i

  validates :action, inclusion: { in: ACTIONS }
  validates :source, inclusion: { in: SOURCES }

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def self.record!(auditable:, account_id:, action:, changes: {}, label: nil)
    actor = Current.audit_actor || Current.user
    create!(
      account_id: account_id,
      auditable_type: auditable.class.name,
      auditable_id: auditable.id,
      auditable_label: label,
      action: action,
      audited_changes: changes,
      actor_type: actor ? actor.class.name : 'System',
      actor_id: actor&.id,
      actor_label: actor&.name,
      source: Current.audit_source || 'job',
      ip_address: Current.audit_ip,
      request_id: Current.audit_request_id
    )
  end

  # One row per account the user belongs to, like LoginEvent.
  def self.record_session!(user, action, ip_address:, request_id:)
    user.account_users.pluck(:account_id).each do |account_id|
      create!(
        account_id: account_id, auditable_type: 'User', auditable_id: user.id, auditable_label: user.name,
        action: action, actor_type: 'User', actor_id: user.id, actor_label: user.name,
        source: 'login', ip_address: ip_address, request_id: request_id
      )
    end
  end

  def self.scrub_changes(changes, filtered)
    changes.to_h do |field, values|
      sensitive = filtered.include?(field.to_s) || field.to_s.match?(SENSITIVE_KEY)
      [field.to_s, sensitive ? [FILTERED, FILTERED] : values.map { |value| scrub(value) }]
    end
  end

  # Secrets nested in jsonb columns (integration settings, bot config).
  def self.scrub(value)
    case value
    when Hash then value.to_h { |key, nested| [key, key.to_s.match?(SENSITIVE_KEY) ? FILTERED : scrub(nested)] }
    when Array then value.map { |nested| scrub(nested) }
    else value
    end
  end
end
