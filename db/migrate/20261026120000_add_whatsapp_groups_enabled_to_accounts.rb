# WhatsApp groups (QR Code inboxes) become an account switch, on for every
# account today and for the ones created from now on. Super Admin turns it off.
class AddWhatsappGroupsEnabledToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :whatsapp_groups_enabled, :boolean, default: true, null: false
  end
end
