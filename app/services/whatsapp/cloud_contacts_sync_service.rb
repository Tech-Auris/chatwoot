# Imports the address book a WhatsApp Business app number shares when it is
# onboarded by coexistence (webhook field `smb_app_state_sync`, asked for by
# Channels::Whatsapp::CoexistenceSyncRequestJob). Each `add` creates the contact
# in the inbox, or gives an existing one the name saved on the phone, unless
# someone already named it in AurisChat. `remove` is ignored: deleting a
# contact from the phone's address book is no reason to drop it here.
class Whatsapp::CloudContactsSyncService
  include ::Whatsapp::IncomingMessageServiceHelpers

  pattr_initialize [:inbox!, :value!]

  def perform
    Array(value[:state_sync]).each do |item|
      next unless item[:type] == 'contact' && item[:action] == 'add'

      sync_contact(item[:contact] || {})
    end
  end

  private

  def sync_contact(data)
    phone = data[:phone_number].to_s.gsub(/\D/, '')
    name = data[:full_name].presence || data[:first_name].presence
    return if phone.blank? || name.blank?

    contact = ::ContactInboxWithContactBuilder.new(
      source_id: processed_waid(phone),
      inbox: inbox,
      contact_attributes: { name: name, phone_number: "+#{phone}" }
    ).perform.contact
    contact.update!(name: name) if contact.name != name && unnamed?(contact, phone)
  end

  def unnamed?(contact, phone)
    contact.name.blank? || ["+#{phone}", TelephoneNumber.parse("+#{phone}").international_number].include?(contact.name)
  end
end
