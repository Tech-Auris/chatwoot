require 'rails_helper'

RSpec.describe Sales::TermsFetcherService do
  let(:url) { described_class::DEFAULT_URL }

  it 'keeps the formatting a contract is read with' do
    stub_request(:get, url).to_return(
      status: 200,
      body: '<html><body><h1>Termos</h1><p>Cláusula <strong>primeira</strong>.</p><ul><li>Item</li></ul></body></html>'
    )

    version = described_class.new.perform

    expect(version.content).to include('<h1>Termos</h1>')
    expect(version.content).to include('<strong>primeira</strong>')
    expect(version.content).to include('<li>Item</li>')
    expect(version.content_hash).to be_present
  end

  # Sanitizing alone keeps the text inside a script tag when it drops the tag,
  # so the nodes are removed before sanitizing.
  it 'drops scripts entirely, not just their tags' do
    stub_request(:get, url).to_return(
      status: 200,
      body: '<html><body><script>alert("xss")</script><p>Cláusula.</p></body></html>'
    )

    content = described_class.new.perform.content

    expect(content).not_to include('alert')
    expect(content).to include('<p>Cláusula.</p>')
  end

  it 'strips attributes that could carry behaviour' do
    stub_request(:get, url).to_return(
      status: 200,
      body: '<html><body><p onclick="steal()" style="color:red">Cláusula.</p></body></html>'
    )

    content = described_class.new.perform.content

    expect(content).not_to include('onclick')
    expect(content).not_to include('style')
  end

  # Storing the raw page would make the hash move on every markup tweak, and
  # every tweak would look like a new contract in the audit trail.
  it 'ignores scripts and layout chrome' do
    stub_request(:get, url).to_return(
      status: 200,
      body: '<html><head><style>.a{}</style></head><body><nav>Menu</nav><p>Cláusula 1.</p><footer>Rodapé</footer><script>x()</script></body></html>'
    )

    expect(described_class.new.perform.content).to eq('<p>Cláusula 1.</p>')
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

  # ApplicationRecord caps every text column at 20k unless the model says
  # otherwise, and a contract runs well past that. Before the model declared its
  # own limit, reaching the payment step answered 422.
  it 'stores a contract longer than the default column ceiling' do
    long_terms = "<p>#{'cláusula ' * 5_000}</p>"
    stub_request(:get, described_class::DEFAULT_URL).to_return(status: 200, body: long_terms)

    version = described_class.new.perform

    expect(version.content.length).to be > 20_000
  end

  it 'refuses a page that came back empty instead of failing to save it' do
    stub_request(:get, described_class::DEFAULT_URL).to_return(status: 200, body: '<html><body></body></html>')

    expect { described_class.new.perform }.to raise_error(described_class::Unavailable, /vazios/)
  end

  it 'explains a version that cannot be stored' do
    stub_request(:get, described_class::DEFAULT_URL).to_return(status: 200, body: "<p>#{'x' * 600_000}</p>")

    expect { described_class.new.perform }.to raise_error(described_class::Unavailable, /não foi possível registrar os termos/i)
  end

  # The marketing page stamps its edition as "Última atualização: 3 de Set de
  # 2026." The super_admin report needs that date next to the wording so the
  # campaign can point at a specific version.
  describe 'document date extraction' do
    it 'reads the "Última atualização" line with an abbreviated month' do
      stub_request(:get, described_class::DEFAULT_URL).to_return(
        status: 200,
        body: '<html><body><p>Última atualização: 3 de Set de 2026.</p><p>Cláusula.</p></body></html>'
      )

      expect(described_class.new.perform.document_date).to eq(Date.new(2026, 9, 3))
    end

    it 'reads the same line with the full month name' do
      stub_request(:get, described_class::DEFAULT_URL).to_return(
        status: 200,
        body: '<html><body><p>Última atualização: 25 de Maio de 2026.</p><p>Cláusula.</p></body></html>'
      )

      expect(described_class.new.perform.document_date).to eq(Date.new(2026, 5, 25))
    end

    # Absent or unparseable stamp lets the wizard prompt the super_admin
    # instead of guessing — better a manual date than a wrong one.
    it 'leaves document_date nil when the line is missing' do
      stub_request(:get, described_class::DEFAULT_URL).to_return(status: 200, body: '<p>Cláusula.</p>')

      expect(described_class.new.perform.document_date).to be_nil
    end

    it 'reuses the version on a second fetch of the same wording' do
      stub_request(:get, described_class::DEFAULT_URL).to_return(
        status: 200, body: '<p>Última atualização: 3 de Set de 2026.</p><p>Cláusula.</p>'
      )

      first = described_class.new.perform
      second = described_class.new.perform

      expect(second.id).to eq(first.id)
      expect(second.document_date).to eq(Date.new(2026, 9, 3))
    end
  end
end
