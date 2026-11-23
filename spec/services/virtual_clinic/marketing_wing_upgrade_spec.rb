require 'rails_helper'

RSpec.describe VirtualClinic::MarketingWingUpgrade do
  let(:saved) do
    {
      'floors' => Array.new(4, '5_pisos/madeira_gerencia.png'),
      'walls' => Array.new(3, '6_paredes/bege_gerencia.png'),
      'items' => [
        { 'sprite' => '1_recepcao/relogio.png', 'x' => 290, 'y' => 15 },
        { 'sprite' => '3_gerencia/quadro_graficos.png', 'x' => 652, 'y' => 8 },
        { 'sprite' => '3_gerencia/sofa_lateral.png', 'x' => 928, 'y' => 196 },
        { 'sprite' => '4_copa/geladeira.png', 'x' => 648, 'y' => 332 }
      ],
      'rooms' => { 'MANAGEMENT' => 'Diretoria' },
      'team' => { 'manager' => { 'name' => 'Marta', 'sheet' => '8_pessoas/pessoa_01.png', 'x' => 708, 'y' => 90 },
                  'secretary' => { 'sheet' => '8_pessoas/pessoa_02.png', 'x' => 304, 'y' => 87 } }
    }
  end
  let(:upgraded) { described_class.call(saved) }

  it 'moves the gerência and Helena to the new wing, pulling up what no longer fits' do
    expect(upgraded['items'].first(4)).to eq(
      [{ 'sprite' => '1_recepcao/relogio.png', 'x' => 290, 'y' => 15 },
       { 'sprite' => '3_gerencia/quadro_graficos.png', 'x' => 972, 'y' => 8 },
       { 'sprite' => '3_gerencia/sofa_lateral.png', 'x' => 1248, 'y' => 172 },
       { 'sprite' => '4_copa/geladeira.png', 'x' => 648, 'y' => 332 }]
    )
    expect(upgraded['team']['manager']).to include('name' => 'Marta', 'x' => 1028, 'y' => 90)
    expect(upgraded['team']['secretary']).to eq(saved['team']['secretary'])
    expect(upgraded['rooms']).to eq('MANAGEMENT' => 'Diretoria')
  end

  it 'adds the sala de marketing furniture, the new half of the copa and the new floors and walls' do
    expect(upgraded['items'].drop(4)).to eq(described_class::NEW_ITEMS)
    expect(upgraded['floors'].size).to eq(VirtualClinic::LayoutValidator::FLOORS)
    expect(upgraded['walls'].size).to eq(VirtualClinic::LayoutValidator::WALLS)
  end

  it 'gives a layout the validator accepts' do
    assets = (upgraded['floors'] + upgraded['walls'] + upgraded['items'].pluck('sprite') +
              upgraded['team'].values.pluck('sheet')).to_set

    expect(VirtualClinic::LayoutValidator.new(upgraded, assets: assets).errors).to be_empty
  end

  it 'runs only once' do
    expect(described_class.call(upgraded)).to eq(upgraded)
  end

  it 'leaves alone a layout that only renamed the team' do
    names = { 'team' => { 'manager' => { 'name' => 'Marta' } } }

    expect(described_class.call(names)).to eq(names)
  end
end
