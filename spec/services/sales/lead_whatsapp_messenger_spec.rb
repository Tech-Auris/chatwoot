require 'rails_helper'

RSpec.describe Sales::LeadWhatsappMessenger do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'baileys', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:quote) { create(:sales_quote, prospect_name: 'Fernanda Alarcon', prospect_phone: '+5544988090404') }
  let(:prospects) { instance_double(Sales::ClickupProspectSearchService, find: { phone: '+55 44 98809-0404' }) }

  def send_message(content = 'Olá!')
    described_class.new(quote: quote, content: content).perform
  end

  before do
    InstallationConfig.where(name: 'COMMERCIAL_WHATSAPP_ACCOUNT_ID').first_or_create!(value: account.id.to_s, locked: false)
                      .update!(value: account.id.to_s)
    InstallationConfig.where(name: 'COMMERCIAL_WHATSAPP_INBOX_ID').first_or_create!(value: inbox.id.to_s, locked: false)
                      .update!(value: inbox.id.to_s)
    GlobalConfig.clear_cache
    allow(Sales::ClickupProspectSearchService).to receive(:new).and_return(prospects)
    # The Baileys canonical-phone lookup asks the WhatsApp session; keep the
    # number as given.
    allow(Whatsapp::CanonicalPhoneResolverService).to receive(:new).and_return(instance_double(Whatsapp::CanonicalPhoneResolverService, resolve: nil))
  end

  it 'creates the contact from the ClickUp phone, opens a conversation and sends the message' do
    conversation = send_message

    contact = conversation.contact
    expect(contact).to have_attributes(name: 'Fernanda Alarcon', phone_number: '+5544988090404', account_id: account.id)
    expect(conversation.inbox).to eq(inbox)
    expect(conversation.messages.last).to have_attributes(content: 'Olá!', message_type: 'outgoing')
  end

  it 'reuses the contact saved without the 9th digit instead of duplicating it' do
    existing = create(:contact, account: account, phone_number: '+554488090404')

    expect { send_message }.not_to change(Contact, :count)
    expect(send_message.contact).to eq(existing)
  end

  it 'reuses the open conversation of that inbox' do
    first = send_message

    expect(send_message('De novo').id).to eq(first.id)
  end

  it 'falls back to the proposal phone when ClickUp is unreachable' do
    allow(prospects).to receive(:find).and_raise(StandardError, 'timeout')

    expect(send_message.contact.phone_number).to eq('+5544988090404')
  end

  it 'refuses when the configured inbox does not belong to the configured account' do
    InstallationConfig.find_by(name: 'COMMERCIAL_WHATSAPP_INBOX_ID').update!(value: create(:inbox, account: create(:account)).id.to_s)
    GlobalConfig.clear_cache

    expect { send_message }.to raise_error(described_class::NotConfigured)
  end
end
