require 'rails_helper'

RSpec.describe VirtualClinic::LayoutValidator do
  let(:assets) { %w[5_pisos/madeira.png 6_paredes/bege.png 4_copa/geladeira.png 8_pessoas/pessoa_01.png] }
  let(:layout) do
    {
      'floors' => Array.new(6, '5_pisos/madeira.png'),
      'walls' => Array.new(4, '6_paredes/bege.png'),
      'items' => [{ 'sprite' => '4_copa/geladeira.png', 'x' => 648, 'y' => 332, 'flip' => true }],
      'rooms' => { 'RECEPTION' => 'Recepção Unidade Centro' },
      'team' => { 'secretary' => { 'name' => 'Ana', 'sheet' => '8_pessoas/pessoa_01.png', 'x' => 304, 'y' => 87 } }
    }
  end

  around { |example| I18n.with_locale(:pt_BR) { example.run } }

  def errors_for(value)
    described_class.new(value, assets: assets.to_set).errors
  end

  it 'accepts a clinic edited within the rules' do
    expect(errors_for(layout)).to be_empty
    expect(errors_for({})).to be_empty
  end

  it 'accepts the layout version the editor saves, as a number' do
    expect(errors_for(layout.merge('version' => 1))).to be_empty
    expect(errors_for(layout.merge('version' => '1'))).to eq(['O layout da clínica não está no formato esperado.'])
  end

  it 'refuses art that is not in the pack' do
    layout['items'] << { 'sprite' => '4_copa/sofa_dourado.png', 'x' => 1, 'y' => 1 }
    expect(errors_for(layout)).to eq(['Esta arte não está disponível: 4_copa/sofa_dourado.png.'])
  end

  it 'refuses art from the wrong folder and unknown keys' do
    expect(errors_for(layout.merge('floors' => Array.new(6, '6_paredes/bege.png')))).to eq(['O layout da clínica não está no formato esperado.'])
    expect(errors_for(layout.merge('roof' => []))).to eq(['O layout da clínica não está no formato esperado.'])
    expect(errors_for(layout.merge('walls' => ['6_paredes/bege.png']))).to eq(['O layout da clínica não está no formato esperado.'])
  end

  it 'refuses furniture and teammates outside the clinic' do
    layout['items'] << { 'sprite' => '4_copa/geladeira.png', 'x' => 1290, 'y' => 10 }
    layout['team']['secretary']['y'] = 600
    expect(errors_for(layout)).to contain_exactly('Um móvel ficou fora da clínica: 4_copa/geladeira.png.',
                                                  'secretary precisa ficar dentro da clínica.')
  end

  it 'refuses empty or too long names, and unknown rooms or personas' do
    layout['rooms']['KITCHEN'] = ' '
    layout['team']['secretary']['name'] = 'A' * 41
    expect(errors_for(layout)).to eq(['Os nomes precisam ter entre 1 e 40 caracteres.'])
    expect(errors_for({ 'rooms' => { 'GARAGE' => 'Garagem' } })).to eq(['O layout da clínica não está no formato esperado.'])
    expect(errors_for({ 'team' => { 'financeiro' => {} } })).to eq(['O layout da clínica não está no formato esperado.'])
  end

  it 'accepts a teammate look from the avatar editor made of known layers' do
    assets.push('9_avatar/Body_32x32_07.png', '9_avatar/Eyes_32x32_02.png', '9_avatar/Outfit_05_32x32_02.png')
    look = { 'body' => 'Body_32x32_07', 'eyes' => 'Eyes_32x32_02', 'outfit' => 'Outfit_05_32x32_02' }
    layout['team']['secretary'] = { 'avatar' => look, 'x' => 304, 'y' => 87 }
    expect(errors_for(layout)).to be_empty

    layout['team']['secretary']['avatar'] = look.merge('hair' => 'Hairstyle_99_32x32_01')
    expect(errors_for(layout)).to eq(['Esta arte não está disponível: 9_avatar/Hairstyle_99_32x32_01.png.'])

    layout['team']['secretary']['avatar'] = look.except('outfit')
    expect(errors_for(layout)).to eq(['O layout da clínica não está no formato esperado.'])
  end

  it 'accepts the decoration of a season pack' do
    assets.push('11_natal/arvore_natal.png')
    layout['items'] << { 'sprite' => '11_natal/arvore_natal.png', 'x' => 440, 'y' => 96 }
    expect(errors_for(layout)).to be_empty
  end

  it 'accepts the sala de marketing, its art and the new wing' do
    assets.push('14_marketing/painel_monitores.png')
    layout['items'] << { 'sprite' => '14_marketing/painel_monitores.png', 'x' => 668, 'y' => 8 }
    layout['rooms']['MARKETING'] = 'Marketing'
    layout['team']['marketing'] = { 'sheet' => '8_pessoas/pessoa_01.png', 'x' => 1200, 'y' => 90 }
    expect(errors_for(layout)).to be_empty
  end

  it 'refuses a layout saved before the sala de marketing until it is upgraded' do
    old = layout.merge('floors' => Array.new(4, '5_pisos/madeira.png'), 'walls' => Array.new(3, '6_paredes/bege.png'))
    expect(errors_for(old)).to eq(['O layout da clínica não está no formato esperado.'])
  end

  it 'caps the furniture' do
    layout['items'] = Array.new(201) { { 'sprite' => '4_copa/geladeira.png', 'x' => 1, 'y' => 1 } }
    expect(errors_for(layout)).to eq(['A clínica pode ter no máximo 200 móveis.'])
  end
end
