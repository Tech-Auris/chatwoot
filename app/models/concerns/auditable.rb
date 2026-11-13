# Writes an ActivityLog row whenever the record is created, updated or
# destroyed, inside the same transaction. Turn it on per model:
#
#   auditable except: %i[last_activity_at], filtered: %i[secret], label: ->(r) { r.name }
#
# `only`/`except` pick the tracked fields; an update that touches none of them
# writes nothing. `filtered` fields are logged as changed without their value
# (names like *token, *secret, *password are always filtered). `account` is the
# method or lambda that returns the account id, for models without account_id.
module Auditable
  extend ActiveSupport::Concern

  IGNORED_FIELDS = %w[id created_at updated_at].freeze

  included do
    class_attribute :auditable_options, instance_writer: false
  end

  class_methods do
    def auditable(on: %i[create update destroy], **options)
      self.auditable_options = { account: :account_id, except: [], filtered: [] }.merge(options)

      after_create { record_activity('create', saved_changes.transform_values(&:last).compact) } if on.include?(:create)
      after_update { record_activity('update', saved_changes) } if on.include?(:update)
      after_destroy { record_activity('destroy', attributes.compact) } if on.include?(:destroy)
    end
  end

  # create/destroy pass the attribute values; update passes [before, after].
  def record_activity(action, changes = {})
    account_id = auditable_account_id
    return if account_id.blank?

    tracked = changes.slice(*auditable_fields(changes.keys)).transform_values { |value| activity_values(action, value) }
    return if tracked.empty? && action == 'update'

    changes = ActivityLog.scrub_changes(tracked, auditable_options[:filtered].map(&:to_s))
    ActivityLog.record!(auditable: self, account_id: account_id, action: action, changes: changes, label: auditable_label)
  end

  private

  def auditable_fields(fields)
    fields = fields.map(&:to_s)
    fields &= auditable_options[:only].map(&:to_s) if auditable_options[:only]
    fields - auditable_options[:except].map(&:to_s) - IGNORED_FIELDS
  end

  def activity_values(action, value)
    case action
    when 'create' then [nil, value]
    when 'destroy' then [value, nil]
    else value
    end
  end

  def auditable_account_id
    account = auditable_options[:account]
    account.is_a?(Proc) ? account.call(self) : public_send(account)
  end

  def auditable_label
    label = auditable_options[:label]
    (label ? label.call(self) : try(:name) || try(:title)).to_s.truncate(255).presence
  end
end
