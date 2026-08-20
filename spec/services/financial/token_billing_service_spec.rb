require 'rails_helper'

RSpec.describe Financial::TokenBillingService do
  subject(:service) { described_class.new(prices: prices, client: client) }

  let(:client) { instance_double(Integrations::Stripe::Client) }
  # The unit prices of the invoice the team issues by hand today.
  let(:catalog) do
    [
      stripe_price('price_text', 6, 'Mensagens de Texto'),
      stripe_price('price_media', 10, 'Respostas a imagens, arquivos e transcrições de áudio'),
      stripe_price('price_audio', 49, 'Mensagens de Áudio')
    ]
  end
  let(:prices) { { text: 'price_text', media: 'price_media', audio: 'price_audio' } }
  let(:account) { create(:account, name: 'Cardionorte', stripe_customer_id: 'cus_1') }

  def stripe_price(id, unit_amount, nickname)
    Struct.new(:id, :unit_amount, :currency, :nickname).new(id, unit_amount, 'brl', nickname)
  end

  before { allow(client).to receive(:list_prices).and_return(Struct.new(:data).new(catalog)) }

  describe '#preview' do
    # Reproduces the July invoice: 1.480 × R$0,06 + 129 × R$0,10 + 3 × R$0,49.
    it 'computes the same total the team bills by hand' do
      result = service.preview([{ account_id: account.id, text: 1480, media: 129, audio: 3 }])

      line = result[:lines].first
      expect(line[:total_amount]).to eq(10_317)
      expect(result[:total_amount]).to eq(10_317)
      expect(line[:items].map { |item| item[:amount] }).to eq([8880, 1290, 147])
    end

    it 'adds up every billable customer into the batch total' do
      other = create(:account, stripe_customer_id: 'cus_2')

      result = service.preview(
        [{ account_id: account.id, text: 100, media: 0, audio: 0 },
         { account_id: other.id, text: 0, media: 10, audio: 2 }]
      )

      expect(result[:total_amount]).to eq(600 + 100 + 98)
      expect(result[:billable_count]).to eq(2)
    end

    it 'leaves out the categories with no usage' do
      result = service.preview([{ account_id: account.id, text: 50, media: 0, audio: 0 }])

      expect(result[:lines].first[:items].map { |item| item[:category] }).to eq([:text])
    end

    # These three cases are why the preview exists: they have to be visible
    # before anything is issued, not discovered as a failure afterwards.
    it 'flags an account that nobody reconciled with Stripe' do
      unlinked = create(:account, name: 'Sem Vínculo')

      line = service.preview([{ account_id: unlinked.id, text: 10, media: 0, audio: 0 }])[:lines].first

      expect(line).to include(billable: false, issue: 'conta sem cliente do Stripe vinculado')
    end

    it 'flags an account id that does not exist here' do
      line = service.preview([{ account_id: 999_999, account_name: 'Fantasma', text: 10, media: 0, audio: 0 }])[:lines].first

      expect(line).to include(billable: false, issue: 'conta não encontrada', account_name: 'Fantasma')
    end

    # Internal accounts, courtesy and contracts where usage is bundled: the batch
    # has to leave those out on its own, not depend on someone editing the
    # spreadsheet every month.
    it 'flags an account that is not charged for tokens' do
      account.update!(token_billing_enabled: false)

      line = service.preview([{ account_id: account.id, text: 1480, media: 129, audio: 3 }])[:lines].first

      expect(line).to include(billable: false, issue: 'cobrança de tokens desativada para esta conta')
    end

    it 'bills every account by default' do
      line = service.preview([{ account_id: account.id, text: 10, media: 0, audio: 0 }])[:lines].first

      expect(account.token_billing_enabled).to be true
      expect(line[:billable]).to be true
    end

    it 'flags a customer with nothing to charge instead of issuing an empty invoice' do
      line = service.preview([{ account_id: account.id, text: 0, media: 0, audio: 0 }])[:lines].first

      expect(line).to include(billable: false, issue: 'consumo zerado')
    end

    it 'refuses to price anything when a category has no price chosen' do
      service = described_class.new(prices: { text: 'price_text', media: '', audio: 'price_audio' }, client: client)

      expect { service.preview([{ account_id: account.id, text: 1, media: 0, audio: 0 }]) }
        .to raise_error(described_class::MissingPrices, /Escolha o preço/)
    end

    it 'refuses a price that is no longer in the catalog' do
      service = described_class.new(prices: prices.merge(audio: 'price_apagado'), client: client)

      expect { service.preview([{ account_id: account.id, text: 1, media: 0, audio: 0 }]) }
        .to raise_error(described_class::MissingPrices, /price_apagado/)
    end
  end

  describe '#perform' do
    let(:invoice) { Struct.new(:id, :number, :hosted_invoice_url).new('in_1', 'A-001', 'https://invoice.stripe.com/x') }

    it 'issues one invoice per customer with a line per category' do
      expect(client).to receive(:create_invoice).with(
        customer_id: 'cus_1',
        items: [{ price_id: 'price_text', quantity: 1480 }, { price_id: 'price_media', quantity: 129 },
                { price_id: 'price_audio', quantity: 3 }],
        days_until_due: 7,
        description: 'Cobrança Tokens - Julho/2026',
        metadata: { 'aurischat_billing_source' => 'token_batch', 'aurischat_billing_period' => '2026-07' }
      ).and_return(invoice)

      results = service.perform(
        [{ account_id: account.id, text: 1480, media: 129, audio: 3 }],
        description: 'Cobrança Tokens - Julho/2026', period: '2026-07'
      )

      expect(results.first).to include(status: 'issued', invoice_number: 'A-001', total_amount: 10_317)
    end

    it 'skips the rows the preview had already flagged' do
      unlinked = create(:account)

      results = service.perform([{ account_id: unlinked.id, text: 10, media: 0, audio: 0 }])

      expect(results.first).to include(status: 'skipped', error: 'conta sem cliente do Stripe vinculado')
    end

    # One customer refused by Stripe must not cost the whole batch: the rest
    # still goes out and the report names who failed.
    it 'carries on when Stripe refuses one of the customers' do
      other = create(:account, name: 'Segunda', stripe_customer_id: 'cus_2')
      allow(client).to receive(:create_invoice).with(hash_including(customer_id: 'cus_1'))
                                               .and_raise(Integrations::Stripe::Client::InvalidRequest, 'No such customer')
      allow(client).to receive(:create_invoice).with(hash_including(customer_id: 'cus_2')).and_return(invoice)

      results = service.perform(
        [{ account_id: account.id, text: 10, media: 0, audio: 0 },
         { account_id: other.id, text: 20, media: 0, audio: 0 }]
      )

      expect(results.map { |row| row[:status] }).to eq(%w[failed issued])
      expect(results.first[:error]).to eq('No such customer')
    end
  end
end
