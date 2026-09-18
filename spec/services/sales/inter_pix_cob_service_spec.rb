require 'rails_helper'

RSpec.describe Sales::InterPixCobService do
  let(:inter) { instance_double(Integrations::Inter::Client) }
  let(:quote) do
    create(:sales_quote, status: :signed, payment_method: :pix, billing_cycle: :annual,
                         total_amount: 1_076_400, discount_amount: 0,
                         prospect_name: 'Fábio Rocha', prospect_email: 'fabio@clinica.com',
                         company_name: 'Clínica Cinco', company_document: '11.222.333/0001-81')
  end

  before do
    allow(Integrations::Inter::Client).to receive(:new).and_return(inter)
    allow(inter).to receive(:configured?).and_return(true)
    allow(inter).to receive(:create_cob).and_return({ 'txid' => 'auris_txid_default', 'pixCopiaECola' => 'payload_default' })
    InstallationConfig.where(name: 'INTER_PIX_KEY').first_or_create!(value: 'contato@auris.ia.br')
    GlobalConfig.clear_cache
  end

  it 'opens a cob against the PIX-discounted amount and stores the txid + payload' do
    allow(inter).to receive(:create_cob)
      .and_return({ 'txid' => 'auris_txid_abc', 'pixCopiaECola' => '00020101021126360014br.gov.bcb.pix...' })

    described_class.new(quote: quote).ensure_cob!

    expect(inter).to have_received(:create_cob)
      .with(hash_including(pix_key: 'contato@auris.ia.br', value_cents: quote.effective_charge_amount))
    expect(quote.reload).to have_attributes(inter_txid: 'auris_txid_abc',
                                            inter_pix_payload: start_with('00020101'))
    expect(quote.events.pluck(:event)).to include('inter_pix_cob_created')
  end

  it 'sends the company document as the debtor when the sale is billed to a CNPJ' do
    allow(inter).to receive(:create_cob).and_return({ 'txid' => 'x', 'pixCopiaECola' => 'y' })

    described_class.new(quote: quote).ensure_cob!

    expect(inter).to have_received(:create_cob)
      .with(hash_including(debtor: hash_including(document: '11.222.333/0001-81', name: 'Clínica Cinco')))
  end

  it 'is a no-op when Inter is not configured — the sale still finishes on the static PIX' do
    allow(inter).to receive(:configured?).and_return(false)

    described_class.new(quote: quote).ensure_cob!

    expect(inter).not_to have_received(:create_cob)
    expect(quote.reload.inter_txid).to be_nil
  end

  it 'is idempotent: a retried checkout does not spawn a second cob' do
    quote.update!(inter_txid: 'existing_txid', inter_pix_payload: 'existing_payload')
    allow(inter).to receive(:create_cob)

    described_class.new(quote: quote).ensure_cob!

    expect(inter).not_to have_received(:create_cob)
    expect(quote.reload.inter_txid).to eq('existing_txid')
  end

  # A soft dependency: if Inter is unreachable, the sale carries on with the
  # static PIX and the finance team confirms by hand.
  it 'swallows Inter errors and records them on the audit trail' do
    allow(inter).to receive(:create_cob).and_raise(Integrations::Inter::Client::ProviderUnavailable, 'Inter 502: upstream')

    expect { described_class.new(quote: quote).ensure_cob! }.not_to raise_error
    expect(quote.reload.inter_txid).to be_nil
    expect(quote.events.pluck(:event)).to include('inter_pix_cob_failed')
  end
end
