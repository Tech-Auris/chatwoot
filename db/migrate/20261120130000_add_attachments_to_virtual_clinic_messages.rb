# Charts the manager draws in her answers (render_chart): kept as data
# (type, labels, series), drawn by the dashboard.
class AddAttachmentsToVirtualClinicMessages < ActiveRecord::Migration[7.1]
  def change
    add_column :virtual_clinic_messages, :attachments, :jsonb, null: false, default: []
  end
end
