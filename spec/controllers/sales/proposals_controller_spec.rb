require 'rails_helper'

RSpec.describe 'Public sales proposal', type: :request do
  let(:quote) do
    create(:sales_quote, prospect_phone: '+55 61 98140-2211', reserved_until: 5.days.from_now,
                         prospect_name: 'Maria Souza', prospect_email: 'maria@clinica.com.br',
                         prospect_document: '12345678900', company_name: 'Clínica Cinco')
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

    # The brand is the logo on top; the heading is about the customer's own
    # proposal, and a white-labelled instance shows its own mark.
    it 'shows the installation logo instead of naming the brand in the heading' do
      get "/proposals/#{quote.public_token}"

      expect(response.body).to include('Sua proposta</h1>')
      expect(response.body).to include('/brand-assets/logo.svg')
    end

    it 'shows the proposal once unlocked' do
      unlock
      get "/proposals/#{quote.public_token}"

      expect(response.body).to include(item.name)
      expect(response.body).to include('Condições reservadas até')
    end

    # Whose number this is decides whether the customer can answer at all.
    it 'shows the beginning of the registered number, never the digits it asks for' do
      get "/proposals/#{quote.public_token}"

      expect(response.body).to include('(61) 98140-XXXX')
      expect(response.body).not_to include('2211')
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

    # The clinic custom field is empty in ClickUp at this stage, so the prospect
    # is the one who tells us — it is what will name the account.
    it 'asks for the clinic name' do
      post "/proposals/#{blank_quote.public_token}/unlock",
           params: { access_code: blank_quote.access_code, phone_last4: '2211' }

      get "/proposals/#{blank_quote.public_token}"

      expect(response.body).to include('Nome da clínica')
      expect(response.body).to include('identificar a sua conta')
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
        proposal: { name: 'Maria Souza', company_name: 'Clínica Cinco', email: 'maria@clinica.com.br',
                    phone: quote.prospect_phone, document: '12345678900' }
      }

      follow_redirect!
      expect(response.body).to include('Estas condições valem por')
      expect(response.body).to include(item.name)
    end

    it 'counts down to the reservation deadline and states what is at stake' do
      quote.update!(discount_amount: 10_950)
      post "/proposals/#{quote.public_token}/details", params: {
        proposal: { name: 'Maria', company_name: 'Clínica Cinco', email: 'maria@clinica.com.br',
                    phone: quote.prospect_phone, document: '12345678900' }
      }

      follow_redirect!
      expect(response.body).to include('de desconto garantidos até lá')
    end

    it 'refuses to take the data from someone who never unlocked the link' do
      reset_session_by_reopening

      post "/proposals/#{quote.public_token}/details", params: {
        proposal: { name: 'Invasor', company_name: 'Clínica X', email: 'x@y.com', phone: '+5511900000000', document: '000' }
      }

      expect(quote.reload.prospect_name).not_to eq('Invasor')
    end
  end

  # The proposal has one address and several states; opening it has to land on
  # the step that is still open.
  describe 'where the link lands' do
    before { unlock }

    it 'asks for the missing details first' do
      # Each proposal is unlocked on its own; this one is not the one the outer
      # setup opened.
      post "/proposals/#{blank_quote.public_token}/unlock",
           params: { access_code: blank_quote.access_code, phone_last4: '2211' }

      get "/proposals/#{blank_quote.public_token}"

      expect(response.body).to include('Confirme se este é o número que você usa')
    end

    it 'shows the plan while there is nothing signed' do
      get "/proposals/#{quote.public_token}"

      expect(response.body).to include('Assinar')
    end

    # This is what sent a customer who had already signed back to the signature.
    it 'takes a signed pix sale to the tracking page' do
      quote.update!(status: :signed, payment_method: :pix)

      get "/proposals/#{quote.public_token}"

      expect(response).to redirect_to(sales_proposal_status_path(quote.public_token))
    end

    # A Stripe checkout that was abandoned is finished from the payment page,
    # and the signature already on file is reused there.
    it 'takes a signed monthly card sale back to the payment page' do
      quote.update!(status: :signed, payment_method: :card, billing_cycle: :monthly)

      get "/proposals/#{quote.public_token}"

      expect(response).to redirect_to(sales_proposal_checkout_path(quote.public_token))
    end

    # An AsaaS link is paid outside and confirmed by hand, so there is nothing
    # to retry — the customer belongs on the tracking page.
    it 'takes a signed instalment sale to the tracking page' do
      quote.update!(status: :signed, payment_method: :card, billing_cycle: :annual)

      get "/proposals/#{quote.public_token}"

      expect(response).to redirect_to(sales_proposal_status_path(quote.public_token))
    end

    it 'takes a paid proposal to the tracking page' do
      quote.update!(status: :paid, payment_method: :pix)

      get "/proposals/#{quote.public_token}"

      expect(response).to redirect_to(sales_proposal_status_path(quote.public_token))
    end

    it 'keeps a converted proposal on the tracking page' do
      quote.update!(status: :converted, payment_method: :pix)

      get "/proposals/#{quote.public_token}"

      expect(response).to redirect_to(sales_proposal_status_path(quote.public_token))
    end

    it 'refuses to open the payment page of a proposal already paid' do
      quote.update!(status: :paid, payment_method: :pix)

      get "/proposals/#{quote.public_token}/pagamento"

      expect(response).to redirect_to(sales_proposal_status_path(quote.public_token))
    end

    # A page left open in another tab must not start a second payment.
    it 'refuses a second payment of a proposal already paid' do
      quote.update!(status: :paid, payment_method: :pix)

      post "/proposals/#{quote.public_token}/pagamento", params: { payment_method: 'pix', accept_terms: '1' }

      expect(response).to redirect_to(sales_proposal_status_path(quote.public_token))
      expect(quote.reload.terms_acceptances).to be_empty
    end

    # The bar answers for the contract, and a card saved for the token charges
    # is not a payment.
    it 'holds the bar at the payment while the pix is pending' do
      quote.update!(status: :signed, payment_method: :pix, token_payment_method_id: 'seti_1')

      get "/proposals/#{quote.public_token}/acompanhamento"

      expect(response.body).to include('2. Pagamento')
      expect(response.body).to include('Aguardando a confirmação do seu PIX')
    end
  end

  describe 'the payment step' do
    let(:stripe_client) { instance_double(Integrations::Stripe::Client) }

    before do
      quote.update!(billing_cycle: :annual)
      stub_request(:get, Sales::TermsFetcherService::DEFAULT_URL)
        .to_return(status: 200, body: '<html><body><h1>Termos</h1><p>Conteúdo dos termos.</p></body></html>')
      allow(Integrations::Stripe::Client).to receive(:new).and_return(stripe_client)
      allow(stripe_client).to receive(:create_customer).and_return(Struct.new(:id).new('cus_1'))
      allow(stripe_client).to receive(:update_customer)
      allow(stripe_client).to receive(:list_tax_ids).and_return(Struct.new(:data).new([]))
      allow(stripe_client).to receive(:create_tax_id)
      allow(stripe_client).to receive(:create_checkout_session).and_return(Struct.new(:id, :url).new('cs_1', 'https://checkout.stripe.com/x'))
      unlock
    end

    # The customer reads the terms on the page and signs that exact version; the
    # tests go through the same door.
    def sign_and_pay(method: 'pix', accept: '1', headers: {})
      get "/proposals/#{quote.public_token}/pagamento"
      version_id = response.body[/name="terms_version_id" id="terms_version_id" value="(\d+)"/, 1] ||
                   response.body[/terms_version_id"[^>]*value="(\d+)"/, 1]

      post "/proposals/#{quote.public_token}/pagamento",
           params: { payment_method: method, accept_terms: accept, terms_version_id: version_id }.compact,
           headers: headers
    end

    it 'renders the terms on the page instead of only linking to them' do
      get "/proposals/#{quote.public_token}/pagamento"

      expect(response.body).to include('Conteúdo dos termos')
      expect(response.body).to include('Role até o fim para liberar o aceite')
    end

    # The notice goes unread while it is quiet; somebody who tries to tick the
    # box before reading is told why nothing happened.
    it 'carries the warning it shows when the box is ticked too early' do
      get "/proposals/#{quote.public_token}/pagamento"

      expect(response.body).to include('Role os termos até o fim para liberar o aceite.')
      expect(response.body).to include('text-red-600')
    end

    it 'shows the plan, the pix discount and the instalment cap' do
      get "/proposals/#{quote.public_token}/pagamento"

      expect(response.body).to include('10% de desconto')
      expect(response.body).to include('em até 12x')
    end

    # The signature has to exist before the payment starts, and it has to say
    # where it came from.
    it 'records the signature with the address and the browser' do
      sign_and_pay(headers: { 'HTTP_USER_AGENT' => 'Mozilla/5.0 (Teste)' })

      acceptance = quote.reload.terms_acceptances.last
      expect(acceptance).to have_attributes(status: 'signed', signer_email: quote.prospect_email, user_agent: 'Mozilla/5.0 (Teste)')
      expect(acceptance.ip_address).to be_present
    end

    # A contract that changes after it was signed is not auditable.
    it 'freezes the terms as they read at the moment of signing' do
      sign_and_pay

      expect(quote.reload.terms_acceptances.last.terms_version.content).to include('Conteúdo dos termos')
    end

    it 'refuses to move on without the checkbox' do
      sign_and_pay(method: 'card', accept: nil)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('aceitar os termos')
      expect(quote.reload.terms_acceptances).to be_empty
    end

    # Coming back to the link is how a customer checks on the deal, and the link
    # is the same one from the first day to the last.
    it 'does not sign the terms a second time when the customer comes back' do
      sign_and_pay
      sign_and_pay

      expect(quote.reload.terms_acceptances.status_signed.count).to eq(1)
    end

    it 'signs again only when the wording changed' do
      sign_and_pay
      stub_request(:get, Sales::TermsFetcherService::DEFAULT_URL)
        .to_return(status: 200, body: '<html><body><p>Outra redação dos termos.</p></body></html>')

      sign_and_pay

      expect(quote.reload.terms_acceptances.status_signed.count).to eq(2)
    end

    # Each plan is paid where it belongs: the monthly subscription on Stripe,
    # the long ones in instalments through AsaaS or by PIX.
    it 'offers pix and instalments on a long plan' do
      get "/proposals/#{quote.public_token}/pagamento"

      expect(response.body).to include('PIX')
      expect(response.body).to include('em até 12x')
    end

    # "Total" on a monthly plan is the first invoice, setup fee included; what
    # comes back every month is only the subscription.
    it 'says what the first charge covers and what recurs' do
      quote.update!(billing_cycle: :monthly, subtotal_amount: 389_700, discount_amount: 0, total_amount: 389_700)
      create(:sales_quote_item, sales_quote: quote, name: 'Plataforma Auris', unit_amount: 89_700, recurring_interval: 'month')
      create(:sales_quote_item, sales_quote: quote, name: 'Implantação', unit_amount: 300_000, recurring_interval: nil)

      get "/proposals/#{quote.public_token}/pagamento"

      expect(response.body).to include('Primeira cobrança de')
      expect(response.body).to include('R$ 897,00</strong> por mês')
      expect(response.body).to include('até você cancelar')
    end

    it 'offers only the card on a monthly plan' do
      quote.update!(billing_cycle: :monthly)

      get "/proposals/#{quote.public_token}/pagamento"

      expect(response.body).to include('Cartão de crédito')
      expect(response.body).not_to include('em até')
      expect(response.body).not_to include('% de desconto')
    end

    it 'sends a long plan paid by card to an AsaaS link' do
      asaas = instance_double(Integrations::Asaas::Client)
      allow(Integrations::Asaas::Client).to receive(:new).and_return(asaas)
      allow(asaas).to receive(:create_payment_link)
        .and_return({ 'id' => 'pay_link_1', 'url' => 'https://www.asaas.com/c/pay_link_1' })

      sign_and_pay(method: 'card')

      expect(response).to redirect_to('https://www.asaas.com/c/pay_link_1')
    end

    it 'sends a monthly plan paid by card to the Stripe checkout' do
      quote.update!(billing_cycle: :monthly)

      sign_and_pay(method: 'card')

      expect(response).to redirect_to('https://checkout.stripe.com/x')
    end

    it 'keeps a pix sale here, with what the customer needs to pay' do
      sign_and_pay

      follow_redirect!
      expect(response.body).to include('AURIS AI SERVIÇOS DE TECNOLOGIA LTDA')
      expect(response.body).to include(quote.prospect_phone)
    end

    # Signing has to point at the text the customer actually read; without the
    # version the page rendered, a wording changed in between would be the one
    # on file.
    it 'refuses a signature that does not name the version that was read' do
      post "/proposals/#{quote.public_token}/pagamento", params: { payment_method: 'pix', accept_terms: '1' }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('Recarregue a página')
      expect(quote.reload.terms_acceptances.status_signed).to be_empty
    end

    # Signing against a page nobody could read would leave an empty contract on
    # file, so the flow stops instead.
    it 'stops when the terms page cannot be read' do
      stub_request(:get, Sales::TermsFetcherService::DEFAULT_URL).to_return(status: 503)

      get "/proposals/#{quote.public_token}/pagamento"

      expect(response.body).to include('Termos indisponíveis')
      expect(response.body).not_to include('Role até o fim')
      expect(quote.reload.terms_acceptances.status_signed).to be_empty
    end
  end

  describe 'the token card step' do
    let(:stripe_client) { instance_double(Integrations::Stripe::Client) }

    before do
      quote.update!(status: :paid, payment_method: :card, stripe_customer_id: 'cus_1')
      allow(Integrations::Stripe::Client).to receive(:new).and_return(stripe_client)
      allow(stripe_client).to receive(:create_setup_session).and_return(Struct.new(:id, :url).new('cs_setup', 'https://checkout.stripe.com/setup'))
      unlock
    end

    it 'sends the customer to save a card without charging it' do
      post "/proposals/#{quote.public_token}/tokens"

      expect(stripe_client).to have_received(:create_setup_session).with(hash_including(customer_id: 'cus_1'))
      expect(response).to redirect_to('https://checkout.stripe.com/setup')
    end

    # Nothing was paid yet, so the first answer is not binding.
    it 'offers the way back to change how the subscription is paid' do
      quote.update!(status: :signed, payment_method: :pix)

      get "/proposals/#{quote.public_token}/acompanhamento"

      expect(response.body).to include('Alterar forma de pagamento')
    end

    it 'stops offering it once the money is in' do
      quote.update!(status: :converted, payment_method: :pix)

      get "/proposals/#{quote.public_token}/acompanhamento"

      expect(response.body).not_to include('Alterar forma de pagamento')
    end

    # The team can settle the card question for somebody who has none, and from
    # then on the page stops asking.
    it 'sends a customer whose card was waived past the step' do
      quote.update!(status: :converted, token_payment_method_id: nil, token_card_waived_at: Time.current)

      get "/proposals/#{quote.public_token}/tokens"

      expect(response).to redirect_to(sales_proposal_status_path(quote.public_token))
    end

    it 'stops offering the card on the tracking page once it is waived' do
      quote.update!(status: :converted, token_payment_method_id: nil, token_card_waived_at: Time.current)

      get "/proposals/#{quote.public_token}/acompanhamento"

      expect(response.body).not_to include('Cadastrar cartão dos tokens')
      expect(response.body).to include('sem cartão cadastrado')
    end

    # A PIX sale has no customer in Stripe until the payment is registered by
    # the finance team, and the card for the token charges is saved before
    # that — it has to hang off a customer we can bill later.
    it 'creates the stripe customer of a pix sale before saving the card' do
      quote.update!(status: :signed, payment_method: :pix, stripe_customer_id: nil)
      allow(stripe_client).to receive_messages(create_customer: Struct.new(:id).new('cus_pix'),
                                               list_tax_ids: Struct.new(:data).new([]))
      allow(stripe_client).to receive(:update_customer)
      allow(stripe_client).to receive(:create_tax_id)

      post "/proposals/#{quote.public_token}/tokens"

      expect(stripe_client).to have_received(:create_setup_session).with(hash_including(customer_id: 'cus_pix'))
      expect(quote.reload.stripe_customer_id).to eq('cus_pix')
    end

    # A monthly plan is charged on this same card from here on, and the customer
    # has to be told before registering it.
    it 'warns a monthly customer that the card also carries the subscription' do
      quote.update!(billing_cycle: :monthly)

      get "/proposals/#{quote.public_token}/tokens"

      expect(response.body).to include('também será usado nas')
    end

    it 'does not warn an annual customer, whose plan is already paid' do
      quote.update!(billing_cycle: :annual)

      get "/proposals/#{quote.public_token}/tokens"

      expect(response.body).not_to include('também será usado nas')
    end
  end

  describe 'the status page' do
    before { unlock }

    it 'says the payment is still awaited on a pix sale' do
      quote.update!(status: :signed, payment_method: :pix)

      get "/proposals/#{quote.public_token}/acompanhamento"

      expect(response.body).to include('Aguardando a confirmação do seu PIX')
    end

    it 'says the access is being created once the payment landed' do
      quote.update!(status: :paid)

      get "/proposals/#{quote.public_token}/acompanhamento"

      expect(response.body).to include('Estamos criando o seu acesso')
    end

    it 'points to the token card while it is missing' do
      quote.update!(status: :paid)

      get "/proposals/#{quote.public_token}/acompanhamento"

      expect(response.body).to include('Cadastrar cartão dos tokens')
    end

    it 'stops asking for the card once it is saved' do
      quote.update!(status: :paid, token_payment_method_id: 'seti_1')

      get "/proposals/#{quote.public_token}/acompanhamento"

      expect(response.body).not_to include('Cadastrar cartão dos tokens')
    end

    it 'tells the converted customer the onboarding is under way' do
      quote.update!(status: :converted)

      get "/proposals/#{quote.public_token}/acompanhamento"

      expect(response.body).to include('time já está preparando a implantação')
    end
  end
end
