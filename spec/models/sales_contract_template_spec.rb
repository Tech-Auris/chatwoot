require 'rails_helper'

RSpec.describe SalesContractTemplate do
  it 'starts from the default model as version 1' do
    template = described_class.current

    expect(template.version).to eq(1)
    expect(template.content).to include('CONTRATO DE LICENÇA DE USO DA PLATAFORMA AURIS', '{{razao_social}}')
  end

  it 'saves a new version on every publish and keeps the old ones' do
    described_class.current

    published = described_class.publish!(content: '<p>Nova versão {{cnpj}}</p>', created_by_name: 'Fabio')

    expect(published.version).to eq(2)
    expect(described_class.current).to eq(published)
    expect(described_class.count).to eq(2)
  end

  it 'strips scripts and unknown tags from the content' do
    template = described_class.publish!(content: '<p onclick="x()">Oi</p><script>alert(1)</script>', created_by_name: 'Fabio')

    expect(template.content).to eq('<p>Oi</p>alert(1)')
  end
end
