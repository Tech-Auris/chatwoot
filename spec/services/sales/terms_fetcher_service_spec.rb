require 'rails_helper'

RSpec.describe Sales::TermsFetcherService do
  let(:url) { described_class::DEFAULT_URL }

  it 'freezes the readable text of the page' do
    stub_request(:get, url).to_return(status: 200, body: '<html><body><h1>Termos</h1><p>Conteúdo.</p></body></html>')

    version = described_class.new.perform

    expect(version.content).to eq('Termos Conteúdo.')
    expect(version.content_hash).to be_present
  end

  # Storing the raw page would make the hash move on every markup tweak, and
  # every tweak would look like a new contract in the audit trail.
  it 'ignores scripts and layout chrome' do
    stub_request(:get, url).to_return(
      status: 200,
      body: '<html><head><style>.a{}</style></head><body><nav>Menu</nav><p>Cláusula 1.</p><footer>Rodapé</footer><script>x()</script></body></html>'
    )

    expect(described_class.new.perform.content).to eq('Cláusula 1.')
  end

  it 'reuses the version while the text has not changed' do
    stub_request(:get, url).to_return(status: 200, body: '<p>Mesmo texto</p>')

    first = described_class.new.perform
    second = described_class.new.perform

    expect(second.id).to eq(first.id)
  end

  it 'creates a new version when the wording changes' do
    stub_request(:get, url).to_return(status: 200, body: '<p>Texto antigo</p>')
    first = described_class.new.perform

    stub_request(:get, url).to_return(status: 200, body: '<p>Texto novo</p>')
    second = described_class.new.perform

    expect(second.id).not_to eq(first.id)
  end

  # Signing against a page nobody could read would file an empty contract.
  it 'refuses when the page answers an error' do
    stub_request(:get, url).to_return(status: 503)

    expect { described_class.new.perform }.to raise_error(described_class::Unavailable, /HTTP 503/)
  end

  it 'refuses when the site cannot be reached at all' do
    stub_request(:get, url).to_raise(SocketError.new('getaddrinfo'))

    expect { described_class.new.perform }.to raise_error(described_class::Unavailable, /não foi possível/i)
  end
end
