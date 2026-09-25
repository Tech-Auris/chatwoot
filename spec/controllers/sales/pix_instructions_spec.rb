require 'rails_helper'

RSpec.describe 'Sales proposal PIX instructions', type: :request do
  after { GlobalConfig.clear_cache }

  let(:proposal) do
    create(:sales_quote, status: :signed, payment_method: :pix, total_amount: 1_286_760,
                         prospect_name: 'Fabio Rocha', prospect_email: 'fabio@exemplo.com',
                         prospect_phone: '+5511979859425', prospect_document: '05649318700',
                         company_name: 'Clínica Nefrário')
  end

  # The page is behind the access code, and the session is what remembers it.
  before do
    post "/proposals/#{proposal.public_token}/unlock",
         params: { access_code: proposal.access_code, phone_last4: proposal.prospect_phone.last(4) }
  end

  context 'when the company PIX code is configured' do
    # The company's own static code, which is what Settings ships with.
    let(:payload) do
      '00020101021126360014br.gov.bcb.pix0114618188670001435204000053039865802BR5905AURIS6009SAO PAULO62070503***6304BF67'
    end

    before do
      InstallationConfig.where(name: 'SALES_PIX_PAYLOAD').first_or_create!(value: payload)
      GlobalConfig.clear_cache
    end

    it 'shows who is being paid, the amount to type and the code' do
      get "/proposals/#{proposal.public_token}/obrigado"

      expect(response.body).to include('AURIS AI SERVIÇOS DE TECNOLOGIA LTDA', '61.818.867/0001-43')
      expect(response.body).to include('Confira o valor quando for pagar')
      expect(response.body).to include('R$ 12.867,60')
      # The code carries the total, so the customer confirms rather than types.
      expect(response.body).to include('540812867.60')
    end

    # The customer who closed the tab before paying comes back to this one.
    it 'keeps the instructions on the tracking page while the payment is pending' do
      get "/proposals/#{proposal.public_token}/acompanhamento"

      expect(response.body).to include('Confira o valor quando for pagar', '540812867.60')
    end

    it 'draws the qr code from the same payload' do
      get "/proposals/#{proposal.public_token}/obrigado"

      expect(response.body).to include('data:image/svg+xml;base64,')
    end

    # Semestral and annual plans carry a PIX à-vista discount (5% / 10%);
    # the page has to show the already-discounted value AND inject that
    # same value into the PIX code, or the customer confirms an amount
    # that's larger than what was promised on the checkout step.
    context 'when the plan carries a PIX à-vista discount' do
      let(:proposal) do
        # Annual plan, R$ 12.867,60 de tabela → 10% off = R$ 11.580,84.
        create(:sales_quote, status: :signed, payment_method: :pix,
                             billing_cycle: :annual, total_amount: 1_286_760,
                             prospect_name: 'Fabio Rocha', prospect_email: 'fabio@exemplo.com',
                             prospect_phone: '+5511979859425', prospect_document: '05649318700',
                             company_name: 'Clínica Nefrário')
      end

      # "Total contratado" na parte inferior segue mostrando o valor de
      # contrato (`total_amount`); o teste foca no bloco PIX que carrega o
      # "Valor a pagar" e o QR/copia-e-cola.
      it 'shows the already-discounted amount and injects it into the PIX code' do
        get "/proposals/#{proposal.public_token}/obrigado"

        expect(response.body).to include('R$ 11.580,84')
        expect(response.body).to include('540811580.84')
      end
    end
  end

  context 'when it is not configured yet' do
    before do
      InstallationConfig.where(name: 'SALES_PIX_PAYLOAD').destroy_all
      GlobalConfig.clear_cache
    end

    it 'falls back to telling the customer the team will send the code' do
      get "/proposals/#{proposal.public_token}/obrigado"

      expect(response.body).to include('AURIS AI SERVIÇOS DE TECNOLOGIA LTDA')
      expect(response.body).to include('envia o código do PIX no seu WhatsApp')
      expect(response.body).not_to include('Confira o valor quando for pagar')
    end
  end
end
