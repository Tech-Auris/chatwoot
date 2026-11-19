# The AI team of the Clínica virtual. Each persona is a seat on the map and a
# conversation the clinic owner can open. The secretary will take the name the
# patients know once the account stores it; until then she is Clara.
class VirtualClinic::Persona
  KEYS = %w[secretary manager].freeze
  DEFAULT_NAMES = { 'secretary' => 'Clara', 'manager' => 'Helena' }.freeze

  attr_reader :key

  def self.all
    KEYS.map { |key| new(key) }
  end

  def self.find!(key)
    raise ActiveRecord::RecordNotFound, "Unknown persona #{key}" unless KEYS.include?(key.to_s)

    new(key.to_s)
  end

  def initialize(key)
    @key = key
  end

  def name
    DEFAULT_NAMES.fetch(key)
  end

  def as_json(*)
    { persona: key, name: name }
  end
end
