# == Schema Information
#
# Table name: virtual_clinic_messages
#
#  id            :bigint           not null, primary key
#  attachments   :jsonb            not null
#  content       :text
#  input_tokens  :integer
#  model         :string
#  output_tokens :integer
#  role          :integer          not null
#  status        :integer          default("pending"), not null
#  tool_calls    :jsonb            not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  thread_id     :bigint           not null
#
# Indexes
#
#  index_virtual_clinic_messages_on_thread_id  (thread_id)
#
# Foreign Keys
#
#  fk_rails_...  (thread_id => virtual_clinic_threads.id)
#
class VirtualClinicMessage < ApplicationRecord
  belongs_to :thread, class_name: 'VirtualClinicThread', inverse_of: :messages

  enum :role, { user: 0, assistant: 1 }
  enum :status, { pending: 0, done: 1, failed: 2 }

  # `account_id` is required: the dashboard drops cable events of other accounts.
  def push_event_data
    as_json(only: %i[id role status content tool_calls attachments created_at]).merge('persona' => thread.persona, 'account_id' => thread.account_id)
  end
end
