# The AI team of the Clínica virtual (config/virtual_clinic/personas.yml).
# Each persona is a seat on the map and a conversation the clinic owner can
# open. The secretary will take the name the patients know once the account
# stores it; until then she is Clara.
class VirtualClinic::Persona
  CONFIG = YAML.load_file(Rails.root.join('config/virtual_clinic/personas.yml')).freeze
  KEYS = CONFIG.keys.freeze
  PROMPTS_PATH = Rails.root.join('lib/virtual_clinic/prompts')

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
    config['default_name']
  end

  def tools
    config['tools']
  end

  def suggestions
    config['suggestions']
  end

  def model
    GlobalConfigService.load(config['model_config_key'], config['default_model'])
  end

  def instructions(account:, user:)
    Liquid::Template.parse(PROMPTS_PATH.join("#{key}.liquid").read).render(
      'name' => name, 'clinic_name' => account.name, 'user_name' => user.name,
      'now' => Time.current.in_time_zone(account.reporting_timezone.presence || 'America/Sao_Paulo').strftime('%A, %d/%m/%Y %H:%M')
    )
  end

  def as_json(*)
    { persona: key, name: name, suggestions: suggestions }
  end

  private

  def config
    CONFIG.fetch(key)
  end
end
