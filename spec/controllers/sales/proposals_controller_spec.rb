require 'rails_helper'

RSpec.describe 'Public sales proposal', type: :request do
  let(:quote) { create(:sales_quote, prospect_phone: '+55 61 98140-2211', reserved_until: 5.days.from_now) }
  let!(:item) { create(:sales_quote_item, sales_quote: quote, name: 'Plano Pro', unit_amount: 89_700) }

  # The attempt counter lives in Redis and survives between examples.
  before { Redis::Alfred.with { |conn| conn.keys('sales_proposal_attempts/*').each { |key| conn.del(key) } } }

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
end
