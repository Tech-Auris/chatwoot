require 'rails_helper'

RSpec.describe Sales::ProspectDetailsService do
  let(:client) { instance_double(Integrations::Clickup::Client, configured?: true) }
  let(:details) do
    { name: 'Maria Souza', company_name: 'Clínica Cinco', email: 'maria@clinica.com.br',
      phone: '+55 61 98140-2211', document: '123.456.789-00' }
  end

  def fill(quote, attributes = details)
    described_class.new(quote: quote, attributes: attributes, client: client).perform
  end

  before do
    allow(client).to receive(:set_custom_field)
    allow(client).to receive(:add_comment)
  end

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
    quote = create(:sales_quote, prospect_phone: '+5561981402211', company_name: 'Clínica Cinco')

    fill(quote)

    expect(client).not_to have_received(:set_custom_field)
  end

  it 'ignores formatting when deciding whether the number changed' do
    quote = create(:sales_quote, prospect_phone: '5561981402211', company_name: 'Clínica Cinco')

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

  describe 'the clinic name' do
    # The ClickUp field is empty when the deal starts; the prospect is the one
    # who tells us, and the task is where the team will look for it.
    it 'writes it onto the task when it was missing there' do
      quote = create(:sales_quote, company_name: nil)

      fill(quote)

      expect(client).to have_received(:set_custom_field)
        .with(quote.clickup_task_id, described_class::CLINIC_FIELD_ID, 'Clínica Cinco')
    end

    it 'keeps it on the proposal, which is what names the account' do
      quote = create(:sales_quote, company_name: nil)

      fill(quote)

      expect(quote.reload.company_name).to eq('Clínica Cinco')
    end

    it 'leaves the task alone when the clinic did not change' do
      quote = create(:sales_quote, company_name: 'Clínica Cinco', prospect_phone: '+5561981402211')

      fill(quote)

      expect(client).not_to have_received(:set_custom_field)
    end
  end

  it 'marks the proposal as ready to move on' do
    quote = create(:sales_quote, prospect_phone: nil)

    fill(quote)

    expect(quote.reload).to be_details_complete
  end

  # The seller sees the deal's stage on the Reservations screen, and the
  # confirmation is a step of its own between reserving the proposal and
  # signing the terms.
  describe 'the status transition to details_confirmed' do
    it 'advances a draft the prospect just filled' do
      quote = create(:sales_quote, status: :draft, prospect_phone: nil)

      fill(quote)

      expect(quote.reload.status).to eq('details_confirmed')
    end

    it 'advances a reserved proposal the same way' do
      quote = create(:sales_quote, status: :reserved, prospect_phone: nil)

      fill(quote)

      expect(quote.reload.status).to eq('details_confirmed')
    end

    it 'does not rewind a proposal that is already signed' do
      quote = create(:sales_quote, status: :signed, prospect_phone: nil)

      fill(quote)

      expect(quote.reload.status).to eq('signed')
    end

    # A field left blank keeps the confirmation partial, so the status
    # must not advance yet — otherwise the seller would think the deal
    # can move on when it still cannot.
    it 'leaves the status alone when the prospect skipped a required field' do
      quote = create(:sales_quote, status: :reserved, prospect_phone: nil)

      fill(quote, details.merge(document: ''))

      expect(quote.reload.status).to eq('reserved')
    end
  end

  # The ClickUp task carries the "customer confirmed" moment for
  # whoever picks the deal up after the reserve. Posted only on the
  # transition from incomplete to complete so re-edits do not spam.
  describe 'the ClickUp comment when the customer confirms the details' do
    it 'posts a comment on the first time all fields are complete' do
      quote = create(:sales_quote, status: :reserved, prospect_phone: nil)

      fill(quote)

      expect(client).to have_received(:add_comment) do |task_id, text|
        expect(task_id).to eq(quote.clickup_task_id)
        expect(text).to start_with('Cliente confirmou os dados na proposta.')
        expect(text).to include('Maria Souza')
        expect(text).to include('Clínica Cinco')
        expect(text).to include('maria@clinica.com.br')
      end
    end

    it 'stays silent when a customer edits an already-complete proposal' do
      quote = create(:sales_quote, status: :details_confirmed, prospect_name: 'Maria',
                                   prospect_email: 'maria@clinica.com.br', prospect_phone: '+5561981402211',
                                   prospect_document: '12345678900', company_name: 'Clínica Cinco')

      fill(quote, details.merge(name: 'Maria Correção'))

      expect(client).not_to have_received(:add_comment)
    end

    it 'stays silent when the save still leaves a required field blank' do
      quote = create(:sales_quote, status: :reserved, prospect_phone: nil)

      fill(quote, details.merge(document: ''))

      expect(client).not_to have_received(:add_comment)
    end

    it 'does not fail the save when posting the comment errors' do
      allow(client).to receive(:add_comment).and_raise(Integrations::Clickup::Client::ProviderUnavailable, 'ClickUp 500')
      quote = create(:sales_quote, status: :reserved, prospect_phone: nil)

      expect { fill(quote) }.not_to raise_error
      expect(quote.reload).to be_details_complete
    end
  end
end
