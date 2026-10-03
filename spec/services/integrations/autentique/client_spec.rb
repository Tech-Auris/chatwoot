require 'rails_helper'

RSpec.describe Integrations::Autentique::Client do
  subject(:client) { described_class.new(api_token: 'token-123') }

  let(:endpoint) { 'https://api.autentique.com.br/v2/graphql' }

  def stub_graphql(data: nil, errors: nil, status: 200)
    stub_request(:post, endpoint).to_return(status: status, body: { data: data, errors: errors }.compact.to_json,
                                            headers: { 'Content-Type' => 'application/json' })
  end

  it 'sends the token as a bearer and returns whose account it is' do
    request = stub_graphql(data: { me: { id: '1', name: 'Daniel', email: 'daniel@agenteauris.com.br' } })

    expect(client.me).to include('name' => 'Daniel', 'email' => 'daniel@agenteauris.com.br')
    expect(request.with(headers: { 'Authorization' => 'Bearer token-123' })).to have_been_requested
  end

  it 'uploads the file as a GraphQL multipart request with the signers' do
    request = stub_request(:post, endpoint)
              .with { |req| ['"variables.file"', 'daniel@agenteauris.com.br', 'sandbox: true'].all? { |part| req.body.include?(part) } }
              .to_return(status: 200, body: { data: { createDocument: { id: 'doc-1' } } }.to_json,
                         headers: { 'Content-Type' => 'application/json' })

    document = client.create_document(name: 'Contrato', io: StringIO.new('%PDF-1.4'), filename: 'contrato.pdf', sandbox: true,
                                      signers: [{ email: 'daniel@agenteauris.com.br', action: 'SIGN' }])

    expect(document).to eq('id' => 'doc-1')
    expect(request).to have_been_requested
  end

  # HTTParty's streamed multipart only delivered the first part; the whole
  # body is sent at once so `map` and the file reach Autentique.
  it 'sends the operations, the map and the file as separate parts' do
    request = stub_request(:post, endpoint)
              .with(headers: { 'Content-Type' => %r{multipart/form-data; boundary=} }) do |req|
                ['name="operations"', 'name="map"', 'name="file"; filename="contrato.pdf"'].all? { |part| req.body.include?(part) }
              end
              .to_return(status: 200, body: { data: { createDocument: { id: 'doc-1' } } }.to_json, headers: { 'Content-Type' => 'application/json' })

    client.create_document(name: 'Contrato', io: StringIO.new('%PDF-1.4'), filename: 'contrato.pdf', signers: [])

    expect(request).to have_been_requested
  end

  it 'raises Unauthorized when Autentique does not recognize the token' do
    stub_graphql(errors: [{ message: 'Unauthenticated.' }])

    expect { client.me }.to raise_error(described_class::Unauthorized)
  end

  it 'raises Error with the GraphQL error messages' do
    stub_graphql(errors: [{ message: 'signature_not_found' }])

    expect { client.sign_document('doc-1') }.to raise_error(described_class::Error, 'signature_not_found')
  end

  it 'raises ProviderUnavailable when Autentique is down' do
    stub_graphql(status: 502)

    expect { client.document('doc-1') }.to raise_error(described_class::ProviderUnavailable)
  end
end
