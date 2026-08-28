require 'rails_helper'

RSpec.describe Sales::ProspectDetailsService do
  let(:client) { instance_double(Integrations::Clickup::Client, configured?: true) }
  let(:details) do
    { name: 'Maria Souza', email: 'maria@clinica.com.br', phone: '+55 61 98140-2211', document: '123.456.789-00' }
  end

  def fill(quote, attributes = details)
    described_class.new(quote: quote, attributes: attributes, client: client).perform
  end

  before { allow(client).to receive(:set_custom_field) }

  it 'records what the prospect filled in' do
    quote = create(:sales_quote, prospect_phone: nil, prospect_name: nil)

    fill(quote)

    expect(quote.reload).to have_attributes(
      prospect_name: 'Maria Souza', prospect_email: 'maria@clinica.com.br', prospect_document: '123.456.789-00'
    )
  end

  # The task had no phone, so the number the prospect just gave us fills the gap.
  it 'writes the phone to the ClickUp task when the task had none' do
    quote = create(:sales_quote, prospect_phone: nil)

    fill(quote)

    expect(client).to have_received(:set_custom_field)
      .with(quote.clickup_task_id, described_class::PHONE_FIELD_ID, '+55 61 98140-2211')
  end

  # Confirming the number that was already there changes nothing — there is
  # nothing to correct, and ClickUp stays the source of truth.
  it 'leaves the task alone when the prospect confirms the same number' do
    quote = create(:sales_quote, prospect_phone: '+5561981402211')

    fill(quote)

    expect(client).not_to have_received(:set_custom_field)
  end

  it 'ignores formatting when deciding whether the number changed' do
    quote = create(:sales_quote, prospect_phone: '5561981402211')

    fill(quote)

    expect(client).not_to have_received(:set_custom_field)
  end

  it 'corrects the task when the prospect gives a different number' do
    quote = create(:sales_quote, prospect_phone: '+5561999999999')

    fill(quote)

    expect(client).to have_received(:set_custom_field)
      .with(quote.clickup_task_id, described_class::PHONE_FIELD_ID, '+55 61 98140-2211')
  end

  # Next time the prospect opens the link, the gate has to ask for the digits
  # they actually use.
  it 'moves the access check to the confirmed number' do
    quote = create(:sales_quote, prospect_phone: '+5561999999999')

    fill(quote)

    expect(quote.reload.verification_phone_last4).to eq('2211')
  end

  it 'keeps the details even when ClickUp refuses the update' do
    allow(client).to receive(:set_custom_field).and_raise(Integrations::Clickup::Client::ProviderUnavailable, 'ClickUp 503')
    quote = create(:sales_quote, prospect_phone: nil)

    result = fill(quote)

    expect(quote.reload.prospect_name).to eq('Maria Souza')
    expect(result).to have_attributes(clickup_synced: false, clickup_error: 'ClickUp 503')
  end

  it 'marks the proposal as ready to move on' do
    quote = create(:sales_quote, prospect_phone: nil)

    fill(quote)

    expect(quote.reload).to be_details_complete
  end
end
