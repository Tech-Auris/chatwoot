# When the manager asks the secretary something (delegation), that talk is
# kept as a child thread of the manager's answer, for audit.
class AddParentMessageToVirtualClinicThreads < ActiveRecord::Migration[7.1]
  def change
    add_reference :virtual_clinic_threads, :parent_message, foreign_key: { to_table: :virtual_clinic_messages, on_delete: :cascade }
  end
end
