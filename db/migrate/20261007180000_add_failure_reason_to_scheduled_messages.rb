# Why a scheduled message did not go out (e.g. the number was disconnected at
# send time), shown next to the failed status.
class AddFailureReasonToScheduledMessages < ActiveRecord::Migration[7.1]
  def change
    add_column :scheduled_messages, :failure_reason, :string
  end
end
