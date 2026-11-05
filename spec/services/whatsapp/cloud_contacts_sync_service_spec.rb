require 'rails_helper'

describe Whatsapp::CloudContactsSyncService do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }

  def sync(*items)
    described_class.new(inbox: inbox, value: { state_sync: items }.with_indifferent_access).perform
  end

  def contact_item(phone, name, action: 'add')
    { type: 'contact', action: action, contact: { full_name: name, first_name: name.split.first, phone_number: phone } }
  end

  it 'creates the contacts of the address book with the name saved on the phone' do
    sync(contact_item('5511988887777', 'Maria Souza'))

    contact = inbox.contact_inboxes.sole.contact
    expect([contact.name, contact.phone_number]).to eq(['Maria Souza', '+5511988887777'])
  end

  it 'names a contact that only had its phone number as name' do
    contact = create(:contact, account: inbox.account, name: '+5511988887777', phone_number: '+5511988887777')

    sync(contact_item('5511988887777', 'Maria Souza'))

    expect(contact.reload.name).to eq('Maria Souza')
  end

  it 'keeps a name already given in AurisChat' do
    contact = create(:contact, account: inbox.account, name: 'Maria (paciente VIP)', phone_number: '+5511988887777')

    sync(contact_item('5511988887777', 'Maria Souza'))

    expect(contact.reload.name).to eq('Maria (paciente VIP)')
  end

  it 'ignores contacts removed from the address book' do
    sync(contact_item('5511988887777', 'Maria Souza', action: 'remove'))

    expect(inbox.contact_inboxes).to be_empty
  end
end
