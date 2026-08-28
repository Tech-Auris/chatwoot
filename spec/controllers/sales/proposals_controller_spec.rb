require 'rails_helper'

RSpec.describe 'Public sales proposal', type: :request do
  let(:quote) do
    create(:sales_quote, prospect_phone: '+55 61 98140-2211', reserved_until: 5.days.from_now,
                         prospect_name: 'Maria Souza', prospect_email: 'maria@clinica.com.br',
                         prospect_document: '12345678900')
  end
  # A proposal whose prospect has not filled anything in yet.
  let(:blank_quote) { create(:sales_quote, prospect_phone: '+55 61 98140-2211', reserved_until: 5.days.from_now) }
  let!(:item) { create(:sales_quote_item, sales_quote: quote, name: 'Plano Pro', unit_amount: 89_700) }

  # The attempt counter lives in Redis and survives between examples.
  before { Redis::Alfred.with { |conn| conn.keys('sales_proposal_attempts/*').each { |key| conn.del(key) } } }

  # A new session stands in for somebody who reached the URL without the code.
  def reset_session_by_reopening
    reset!
  end

  def unlock(code: quote.access_code, phone: '2211')
    post "/proposals/#{quote.public_token}/unlock", params: { access_code: code, phone_last4: phone }
  end

  describe 'GET /proposals/:token' do
    # The prospect has no login, so the page asks for what the seller sent
    # before showing anything about the deal.
    it 'asks for the code before showing the proposal' do
      get "/proposals/#{quote.public_token}"

      expect(response.body).to include('4 últimos dígitos')
      expect(response.body).not_to include('Plano Pro')
    end

    it 'shows the proposal once unlocked' do
      unlock
      get "/proposals/#{quote.public_token}"

      expect(response.body).to include(item.name)
      expect(response.body).to include('Condições reservadas até')
    end

    it 'answers 404 for a token that does not exist' do
      get '/proposals/inventado'

      expect(response).to have_http_status(:not_found)
    end

    # An expired reservation does not close the page — it stops promising the
    # discounted conditions.
    it 'says the reservation lapsed instead of hiding the proposal' do
      quote.update!(reserved_until: 1.day.ago)
      unlock
      get "/proposals/#{quote.public_token}"

      expect(response.body).to include('A reserva venceu em')
    end
  end

  describe 'POST /proposals/:token/unlock' do
    it 'refuses the right code with the wrong phone digits' do
      unlock(phone: '9999')

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).to include('não conferem')
    end

    it 'records that the prospect opened it, which nothing else can tell us' do
      expect { unlock }.to change { quote.events.where(event: 'opened_by_prospect').count }.by(1)
    end

    # Six digits plus four is only safe while guessing stays slow.
    it 'stops answering after too many attempts from the same address' do
      (Sales::ProposalsController::ATTEMPT_LIMIT + 1).times { unlock(code: '000000') }

      expect(response).to have_http_status(:too_many_requests)
      expect(response.body).to include('Muitas tentativas')
    end
  end

  describe 'the details step' do
    let(:clickup_client) { instance_double(Integrations::Clickup::Client, configured?: true) }

    before do
      allow(Integrations::Clickup::Client).to receive(:new).and_return(clickup_client)
      allow(clickup_client).to receive(:set_custom_field)
      unlock
    end

    # The contract and the invoice need to know who the customer is, so the
    # summary only comes after the form.
    it 'asks for the data before showing the confirmation' do
      post "/proposals/#{blank_quote.public_token}/unlock",
           params: { access_code: blank_quote.access_code, phone_last4: '2211' }

      get "/proposals/#{blank_quote.public_token}"

      expect(response.body).to include('Confirme seus dados')
      expect(response.body).not_to include('Estas condições valem por')
    end

    it 'shows the number already on file to be confirmed rather than asking again' do
      post "/proposals/#{blank_quote.public_token}/unlock",
           params: { access_code: blank_quote.access_code, phone_last4: '2211' }

      get "/proposals/#{blank_quote.public_token}"

      expect(response.body).to include(blank_quote.prospect_phone)
      expect(response.body).to include('Confirme se este é o número que você usa')
    end

    it 'moves on to the confirmation once the data is filled' do
      post "/proposals/#{quote.public_token}/details", params: {
        proposal: { name: 'Maria Souza', email: 'maria@clinica.com.br', phone: quote.prospect_phone, document: '12345678900' }
      }

      follow_redirect!
      expect(response.body).to include('Estas condições valem por')
      expect(response.body).to include(item.name)
    end

    it 'counts down to the reservation deadline and states what is at stake' do
      quote.update!(discount_amount: 10_950)
      post "/proposals/#{quote.public_token}/details", params: {
        proposal: { name: 'Maria', email: 'maria@clinica.com.br', phone: quote.prospect_phone, document: '12345678900' }
      }

      follow_redirect!
      expect(response.body).to include('de desconto garantidos até lá')
    end

    it 'refuses to take the data from someone who never unlocked the link' do
      reset_session_by_reopening

      post "/proposals/#{quote.public_token}/details", params: {
        proposal: { name: 'Invasor', email: 'x@y.com', phone: '+5511900000000', document: '000' }
      }

      expect(quote.reload.prospect_name).not_to eq('Invasor')
    end
  end
end
