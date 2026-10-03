require 'rails_helper'

RSpec.describe Sales::ContractDeadlineJob do
  let(:quote) { create(:sales_quote, billing_cycle: :annual, reserved_until: 10.days.from_now) }
  let(:client) { instance_double(Integrations::Autentique::Client, update_deadline: {}) }

  before { allow(Integrations::Autentique::Client).to receive(:new).and_return(client) }

  it 'moves the signing deadline to the new reservation date and reopens an expired contract' do
    contract = create(:sales_contract, sales_quote: quote, status: :expired, deadline_at: 1.day.ago, autentique_document_id: 'doc-9')

    described_class.perform_now(contract.id)

    expect(client).to have_received(:update_deadline).with('doc-9', quote.reserved_until)
    expect(contract.reload).to have_attributes(status: 'awaiting_signature', deadline_at: quote.reserved_until)
  end
end
