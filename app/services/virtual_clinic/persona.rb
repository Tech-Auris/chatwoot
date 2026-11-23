# The AI team of the Clínica virtual (config/virtual_clinic/personas.yml).
# Each persona is a seat on the map and a conversation the clinic owner can
# open. Their names (Clara, Helena and Luciano by default) can be changed in the
# clinic editor; that name only applies inside the Clínica virtual.
class VirtualClinic::Persona
  CONFIG = YAML.load_file(Rails.root.join('config/virtual_clinic/personas.yml')).freeze
  KEYS = CONFIG.keys.freeze
  PROMPTS_PATH = Rails.root.join('lib/virtual_clinic/prompts')

  attr_reader :key

  def self.all(account: nil)
    KEYS.map { |key| new(key, account: account) }
  end

  def self.find!(key, account: nil)
    raise ActiveRecord::RecordNotFound, "Unknown persona #{key}" unless KEYS.include?(key.to_s)

    new(key.to_s, account: account)
  end

  def initialize(key, account: nil)
    @key = key
    @account = account
  end

  def name
    @account&.virtual_clinic_layout&.team_name(key) || config['default_name']
  end

  def tools
    config['tools']
  end

  def role
    config['role']
  end

  # Whether only administrators and managers see what the persona is doing
  # (its numbers on the map and its alerts).
  def restricted?
    config['restricted'] == true
  end

  # Whether the persona can answer with charts (RenderChartTool).
  def charts?
    config['charts'] == true
  end

  def scope
    config['scope']
  end

  # The teammates this persona can ask (see AskTeammateTool).
  def teammates
    Array(config['delegates_to']).map { |teammate| self.class.find!(teammate, account: @account) }
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
      'secretary_name' => self.class.find!('secretary', account: account).name,
      'manager_name' => self.class.find!('manager', account: account).name,
      'marketing_name' => self.class.find!('marketing', account: account).name,
      'now' => Time.current.in_time_zone(account.reporting_timezone.presence || 'America/Sao_Paulo').strftime('%A, %d/%m/%Y %H:%M')
    )
  end

  def as_json(*)
    { persona: key, name: name, suggestions: suggestions, restricted: restricted? }
  end

  private

  def config
    CONFIG.fetch(key)
  end
end
