require 'rails_helper'

RSpec.describe Integrations::Inter::Client do
  subject(:client) do
    described_class.new(client_id: 'cid', client_secret: 'csecret',
                        cert_pem: 'stubbed-cert-pem', key_pem: 'stubbed-key-pem')
  end

  # HTTParty parses the mTLS PEMs on every call — a job for real credentials
  # in production, not tests. Bypass the parsing so the WebMock stubs below
  # are what the spec really exercises.
  before { allow_any_instance_of(described_class).to receive(:mtls_options).and_return({}) } # rubocop:disable RSpec/AnyInstance

  let(:token_response) { { 'access_token' => 'access_1', 'expires_in' => 3600 } }
  let(:cob_response) do
    { 'txid' => 'auris_test_txid_00000000000001', 'pixCopiaECola' => '00020101021126360014br.gov.bcb.pix...',
      'status' => 'ATIVA', 'valor' => { 'original' => '897.00' } }
  end

  describe '#configured?' do
    it 'is false while any of the four credentials is missing' do
      expect(described_class.new(client_id: 'x')).not_to be_configured
      expect(described_class.new(client_id: 'x', client_secret: 'y', cert_pem: 'z')).not_to be_configured
    end

    it 'is true only when the whole mTLS + OAuth material is set' do
      expect(client).to be_configured
    end
  end

  describe '#create_cob' do
    before do
      stub_request(:post, 'https://cdpj.partners.bancointer.com.br/oauth/v2/token')
        .to_return(status: 200, body: token_response.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'asks Inter for the token before the first call' do
      request = stub_request(:post, 'https://cdpj.partners.bancointer.com.br/oauth/v2/token')
                .with(body: hash_including('grant_type' => 'client_credentials', 'client_id' => 'cid'))
                .to_return(status: 200, body: token_response.to_json,
                           headers: { 'Content-Type' => 'application/json' })
      stub_request(:put, %r{cdpj\.partners\.bancointer\.com\.br/pix/v2/cob/})
        .to_return(status: 200, body: cob_response.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      client.create_cob(txid: 'auris_test_txid_00000000000001', value_cents: 89_700,
                        pix_key: 'contato@auris.ia.br', description: 'AurisChat — Clínica Cinco')

      expect(request).to have_been_requested
    end

    it 'opens the cob against the given txid with the amount in reais' do
      request = stub_request(:put, 'https://cdpj.partners.bancointer.com.br/pix/v2/cob/auris_txid_1234567890000000000')
                .with(body: hash_including('valor' => hash_including('original' => '897.00'),
                                           'chave' => 'contato@auris.ia.br',
                                           'calendario' => hash_including('expiracao' => 3600)))
                .to_return(status: 200, body: cob_response.to_json,
                           headers: { 'Content-Type' => 'application/json' })

      client.create_cob(txid: 'auris_txid_1234567890000000000', value_cents: 89_700,
                        pix_key: 'contato@auris.ia.br', description: 'Test')

      expect(request).to have_been_requested
    end

    it 'sends the debtor when a document is available, with CPF vs CNPJ picked by length' do
      request = stub_request(:put, %r{cdpj\.partners\.bancointer\.com\.br/pix/v2/cob/})
                .with(body: hash_including('devedor' => hash_including('cnpj' => '11222333000181', 'nome' => 'Clínica Cinco')))
                .to_return(status: 200, body: cob_response.to_json,
                           headers: { 'Content-Type' => 'application/json' })

      client.create_cob(txid: 'auris_txid_1234567890000000000', value_cents: 89_700,
                        pix_key: 'contato@auris.ia.br', description: 'Test',
                        debtor: { document: '11.222.333/0001-81', name: 'Clínica Cinco' })

      expect(request).to have_been_requested
    end

    it 'answers with the payload Inter returned' do
      stub_request(:put, %r{cdpj\.partners\.bancointer\.com\.br/pix/v2/cob/})
        .to_return(status: 200, body: cob_response.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      answer = client.create_cob(txid: 'auris_txid_1234567890000000000', value_cents: 89_700,
                                 pix_key: 'contato@auris.ia.br', description: 'Test')

      expect(answer['pixCopiaECola']).to start_with('00020101')
    end
  end

  describe 'when Inter refuses the call' do
    before do
      stub_request(:post, 'https://cdpj.partners.bancointer.com.br/oauth/v2/token')
        .to_return(status: 200, body: token_response.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'raises Unauthorized on 401' do
      stub_request(:put, %r{cdpj\.partners\.bancointer\.com\.br/pix/v2/cob/})
        .to_return(status: 401, body: '{}')

      expect do
        client.create_cob(txid: 'auris_txid_1234567890000000000', value_cents: 100_00,
                          pix_key: 'k', description: 'x')
      end.to raise_error(described_class::Unauthorized)
    end

    it 'surfaces the Bacen problem-detail on 400' do
      stub_request(:put, %r{cdpj\.partners\.bancointer\.com\.br/pix/v2/cob/})
        .to_return(status: 400,
                   body: { title: 'Requisição inválida', detail: 'txid duplicado' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect do
        client.create_cob(txid: 'auris_txid_1234567890000000000', value_cents: 100_00,
                          pix_key: 'k', description: 'x')
      end.to raise_error(described_class::ProviderUnavailable, /txid duplicado/)
    end
  end
end
