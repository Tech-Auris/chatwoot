class VirtualClinicMessage < ApplicationRecord
  belongs_to :thread, class_name: 'VirtualClinicThread', inverse_of: :messages

  enum :role, { user: 0, assistant: 1 }
  enum :status, { pending: 0, done: 1, failed: 2 }

  # `account_id` is required: the dashboard drops cable events of other accounts.
  def push_event_data
    as_json(only: %i[id role status content tool_calls created_at]).merge('persona' => thread.persona, 'account_id' => thread.account_id)
  end
end
