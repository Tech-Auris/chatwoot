# Moves a layout saved before the sala de marketing (Nov/2026) to the new
# plan: the clinic grew 10 columns to the right, the gerência moved there
# (its saved furniture and Helena go 320 px to the right, pulled up when
# they no longer fit the shorter room) and the sala de marketing took its
# old place with the default furniture, as did the new half of the copa.
# Floors and walls get the new areas.
# Run once, by the migration that ships the new plan.
class VirtualClinic::MarketingWingUpgrade
  SHIFT = 320
  OLD_MANAGEMENT = { x: 640...960, y: ...320 }.freeze
  ROOM_BOTTOM = 248
  # Drawn heights of the gerência art (and the Christmas tree it may have);
  # anything else is taken as 48 px.
  HEIGHTS = {
    '3_gerencia/planta.png' => 56, '3_gerencia/planta_2.png' => 52, '3_gerencia/sofa_lateral.png' => 76,
    '3_gerencia/sofa.png' => 48, '3_gerencia/mesa_em_l.png' => 64, '3_gerencia/arquivo.png' => 44,
    '3_gerencia/arquivo_2.png' => 44, '11_natal/arvore_natal_3.png' => 68
  }.freeze
  DEFAULT_HEIGHT = 48
  NEW_FLOORS = %w[5_pisos/carpete_vinho.png 5_pisos/alternativa_branco_liso.png].freeze
  NEW_WALLS = %w[6_paredes/alternativa_branca.png].freeze
  # The default sala de marketing and new half of the copa (engine/layout.js).
  NEW_ITEMS = [
    { 'sprite' => '14_marketing/painel_monitores.png', 'x' => 668, 'y' => 8 },
    { 'sprite' => '14_marketing/quadro_campanhas.png', 'x' => 792, 'y' => 8 },
    { 'sprite' => '14_marketing/quadro_criativos.png', 'x' => 868, 'y' => 12 },
    { 'sprite' => '14_marketing/planta.png', 'x' => 916, 'y' => 52 },
    { 'sprite' => '14_marketing/cadeira_executiva.png', 'x' => 760, 'y' => 108 },
    { 'sprite' => '14_marketing/mesa.png', 'x' => 744, 'y' => 158 },
    { 'sprite' => '14_marketing/monitor_costas.png', 'x' => 758, 'y' => 150, 'sortY' => 197 },
    { 'sprite' => '14_marketing/monitor_costas.png', 'x' => 787, 'y' => 150, 'sortY' => 197 },
    { 'sprite' => '14_marketing/poltrona_lateral.png', 'x' => 652, 'y' => 186, 'flip' => true },
    { 'sprite' => '14_marketing/planta_2.png', 'x' => 930, 'y' => 196 },
    { 'sprite' => '4_copa/maquina_lanches.png', 'x' => 1010, 'y' => 340 },
    { 'sprite' => '4_copa/cafeteira.png', 'x' => 1072, 'y' => 352 },
    { 'sprite' => '4_copa/cadeira_frente.png', 'x' => 1108, 'y' => 437 },
    { 'sprite' => '4_copa/mesa_redonda.png', 'x' => 1092, 'y' => 470 },
    { 'sprite' => '4_copa/cadeira_lado.png', 'x' => 1068, 'y' => 492, 'flip' => true },
    { 'sprite' => '4_copa/cadeira_lado.png', 'x' => 1148, 'y' => 492 },
    { 'sprite' => '4_copa/planta.png', 'x' => 1240, 'y' => 590 }
  ].freeze

  def self.call(layout)
    new(layout).call
  end

  def initialize(layout)
    @layout = layout.deep_dup
  end

  def call
    return @layout if upgraded?

    @layout['floors'] += NEW_FLOORS if @layout['floors'].is_a?(Array)
    @layout['walls'] += NEW_WALLS if @layout['walls'].is_a?(Array)
    @layout['items'] = @layout['items'].map { |item| move(item, HEIGHTS.fetch(item['sprite'], DEFAULT_HEIGHT)) } + NEW_ITEMS if @layout['items']
    @layout['team']['manager'] = move(@layout['team']['manager'], 64) if @layout.dig('team', 'manager')
    @layout
  end

  private

  def upgraded?
    Array(@layout['items']).any? { |item| item['sprite'].to_s.start_with?('14_marketing/') } ||
      Array(@layout['walls']).size > 3
  end

  def move(spot, height)
    return spot unless OLD_MANAGEMENT[:x].cover?(spot['x']) && OLD_MANAGEMENT[:y].cover?(spot['y'])

    spot.merge('x' => spot['x'] + SHIFT, 'y' => [spot['y'], ROOM_BOTTOM - height].min)
  end
end
