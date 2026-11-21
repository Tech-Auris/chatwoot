# Checks a Clínica virtual layout saved from the editor (see
# VirtualClinicLayout): the expected shape, art that exists in the pack,
# furniture and the AI team inside the clinic, and names of a sane size.
# Whether the team can be reached from the entrance is checked by the editor,
# which has the walk grid.
class VirtualClinic::LayoutValidator
  WORLD_WIDTH = 960
  WORLD_HEIGHT = 640
  FRAME_WIDTH = 32
  FRAME_HEIGHT = 64
  FLOORS = 4
  WALLS = 3
  MAX_ITEMS = 200
  NAME_MAX = 40
  ROOMS = %w[RECEPTION WAITING_ROOM MANAGEMENT KITCHEN].freeze
  FOLDERS = {
    floors: %r{\A5_pisos/},
    walls: %r{\A6_paredes/},
    items: %r{\A([1-4]_[a-z_]+|#{VirtualClinic::Season.folders.join('|')})/},
    team: %r{\A(7_personagens|8_pessoas)/}
  }.freeze

  attr_reader :errors

  def initialize(layout, assets: nil)
    @layout = layout
    @assets = assets
    @errors = []
    validate
  end

  private

  def validate
    return invalid! unless @layout.is_a?(Hash) && (@layout.keys - %w[floors walls items rooms team]).empty?

    check_blocks('floors', FLOORS)
    check_blocks('walls', WALLS)
    check_items
    check_rooms
    check_team
    @errors.uniq!
  end

  def check_blocks(key, size)
    blocks = @layout[key]
    return if blocks.nil?
    return invalid! unless blocks.is_a?(Array) && blocks.size == size

    blocks.each { |path| check_art(path, FOLDERS[key.to_sym]) }
  end

  def check_items
    items = @layout['items']
    return if items.nil?
    return invalid! unless items.is_a?(Array) && items.all?(Hash)
    return add(:too_many_items, max: MAX_ITEMS) if items.size > MAX_ITEMS

    items.each { |item| check_item(item) }
  end

  def check_item(item)
    return invalid! unless integer?(item['x']) && integer?(item['y']) && (item['sortY'].nil? || integer?(item['sortY']))

    check_art(item['sprite'], FOLDERS[:items])
    add(:item_outside, path: item['sprite']) unless inside?(item['x'], item['y'], 0, 0)
  end

  def check_rooms
    rooms = @layout['rooms']
    return if rooms.nil?
    return invalid! unless rooms.is_a?(Hash) && (rooms.keys - ROOMS).empty?

    rooms.each_value { |name| check_name(name) }
  end

  def check_team
    team = @layout['team']
    return if team.nil?
    return invalid! unless team.is_a?(Hash) && (team.keys - VirtualClinic::Persona::KEYS).empty?

    team.each { |persona, seat| check_seat(persona, seat) }
  end

  def check_seat(persona, seat)
    return invalid! unless seat.is_a?(Hash) && integer?(seat['x']) && integer?(seat['y'])

    check_look(seat)
    check_name(seat['name']) if seat.key?('name')
    add(:team_outside, persona: persona) unless inside?(seat['x'], seat['y'], FRAME_WIDTH, FRAME_HEIGHT)
  end

  # A premade spritesheet, or a look of the avatar editor.
  def check_look(seat)
    return check_art(seat['sheet'], FOLDERS[:team]) unless seat.key?('avatar')
    return invalid! unless VirtualClinic::Avatar.sanitize(seat['avatar'])

    VirtualClinic::Avatar.paths(seat['avatar']).each { |path| check_art(path, %r{\A9_avatar/}) }
  end

  def check_art(path, folder)
    return invalid! unless path.is_a?(String) && folder.match?(path)

    add(:unknown_art, path: path) unless assets.include?(path)
  end

  def check_name(name)
    add(:name_length, max: NAME_MAX) unless name.is_a?(String) && name.strip.length.between?(1, NAME_MAX)
  end

  def inside?(left, top, width, height)
    left.between?(0, WORLD_WIDTH - width) && top.between?(0, WORLD_HEIGHT - height)
  end

  def integer?(value)
    value.is_a?(Integer)
  end

  def assets
    @assets ||= VirtualClinic::AssetStore.list.to_set
  end

  def invalid!
    add(:invalid)
  end

  def add(key, **vars)
    @errors << I18n.t("virtual_clinic.layout.errors.#{key}", **vars)
  end
end
