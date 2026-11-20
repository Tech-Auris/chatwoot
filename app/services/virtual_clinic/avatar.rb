# A look made in the Clínica virtual avatar editor: a premade character of
# the pack (`{ "sheet" => "8_pessoas/pessoa_03.png" }`) or the layers of the
# LimeZu character generator (art folder `9_avatar/`) it is drawn with, as
# `{ "body" => "Body_32x32_07", "eyes" => ..., "outfit" => ..., "hair" => ...,
# "accessory" => ... }`. Body, eyes and outfit are required.
class VirtualClinic::Avatar
  FOLDER = '9_avatar'.freeze
  PARTS = { 'body' => 'Body_', 'eyes' => 'Eyes_', 'outfit' => 'Outfit_', 'hair' => 'Hairstyle_', 'accessory' => 'Accessory_' }.freeze
  REQUIRED = %w[body eyes outfit].freeze
  LAYER_FORMAT = /\A[0-9A-Za-z_]+\z/
  PREMADE_FORMAT = %r{\A(7_personagens|8_pessoas)/[0-9A-Za-z_]+\.png\z}

  # The look as sent by a client, or nil when it isn't one.
  def self.sanitize(look)
    return unless look.is_a?(Hash)

    look.key?('sheet') ? premade(look) : layers(look)
  end

  def self.layers(look)
    return unless (look.keys - PARTS.keys).empty? && REQUIRED.all? { |part| look[part].present? }

    look if look.all? { |part, layer| layer?(part, layer) }
  end

  def self.premade(look)
    look if look.keys == ['sheet'] && look['sheet'].is_a?(String) && PREMADE_FORMAT.match?(look['sheet'])
  end

  def self.layer?(part, layer)
    layer.is_a?(String) && LAYER_FORMAT.match?(layer) && layer.start_with?(PARTS[part])
  end

  def self.paths(look)
    look.values.map { |layer| "#{FOLDER}/#{layer}.png" }
  end
end
