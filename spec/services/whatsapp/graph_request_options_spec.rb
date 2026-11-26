require 'rails_helper'

describe Whatsapp::GraphRequestOptions do
  let(:guarded_sources) { %w[app/services/whatsapp/facebook_api_client.rb app/services/whatsapp/health_service.rb] }

  # Reads each `HTTParty.x(` call up to its matching paren, so the options found belong to that call.
  def graph_calls(source)
    source.to_enum(:scan, /HTTParty\.(?:get|post|put|patch|delete)\(/).map do
      start = Regexp.last_match.begin(0)
      depth = 0
      length = source[start..].each_char.with_index.find do |char, _|
        depth += 1 if char == '('
        depth -= 1 if char == ')'
        char == ')' && depth.zero?
      end.last
      source[start, length + 1]
    end
  end

  it 'reads a call to its own closing paren, not to the first one it meets' do
    source = <<~RUBY
      HTTParty.get(
        "\#{BASE_URI}/x",
        query: { token: GlobalConfigService.load('A', '') },
        **GRAPH_REQUEST_OPTIONS
      )
    RUBY

    expect(graph_calls(source).first).to include('GRAPH_REQUEST_OPTIONS')
  end

  it 'caps the wait and turns off the retry' do
    expect(described_class::GRAPH_REQUEST_OPTIONS).to eq(timeout: 10, max_retries: 0)
  end

  it 'leaves no Graph call in the guarded files without the ceiling' do
    without_ceiling = guarded_sources.flat_map do |path|
      graph_calls(Rails.root.join(path).read).reject { |call| call.include?('GRAPH_REQUEST_OPTIONS') }
    end

    expect(without_ceiling).to be_empty
  end

  it 'reads every call in the guarded files, so an empty result cannot pass as a clean one' do
    counts = guarded_sources.index_with { |path| graph_calls(Rails.root.join(path).read).size }

    expect(counts).to eq(
      'app/services/whatsapp/facebook_api_client.rb' => 9,
      'app/services/whatsapp/health_service.rb' => 2
    )
  end
end
