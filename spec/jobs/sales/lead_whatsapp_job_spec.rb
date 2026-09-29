require 'rails_helper'

RSpec.describe Sales::LeadWhatsappJob do
  let(:quote) { create(:sales_quote, status: :reserved, reserved_until: 3.days.from_now) }
  let(:messenger) { instance_double(Sales::LeadWhatsappMessenger) }

  before { allow(Sales::LeadWhatsappMessenger).to receive(:new).and_return(messenger) }

  it 'sends the reservation message with the link and access code and records it' do
    allow(messenger).to receive(:perform).and_return(create(:conversation))

    described_class.perform_now(quote.id, 'reservation')

    expect(Sales::LeadWhatsappMessenger).to have_received(:new).with(quote: quote, content: include(quote.access_code))
    expect(quote.events.last.event).to eq('whatsapp_reservation_sent')
  end

  it 'records the failure for the seller instead of retrying' do
    allow(messenger).to receive(:perform).and_raise(Sales::LeadWhatsappMessenger::MissingPhone, 'sem telefone')

    expect { described_class.perform_now(quote.id, 'reservation') }.not_to raise_error
    expect(quote.events.last).to have_attributes(event: 'whatsapp_reservation_failed')
    expect(quote.events.last.metadata['error']).to eq('sem telefone')
  end
end
