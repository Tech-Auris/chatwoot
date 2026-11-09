# The Auris template kit (config/meta_template_kit.yml): the follow-up
# templates installed on every Cloud number, the system templates the Auris
# engine sends by name, and the suggested starting points. The kit is pt_BR
# only, so the clinic data it fills in is written in Portuguese.
module Whatsapp::TemplateKit
  CONFIG = YAML.load_file(Rails.root.join('config/meta_template_kit.yml')).freeze
  LANGUAGE = 'pt_BR'.freeze
  GROUPS = %w[follow_up system suggested].freeze
  # Groups whose rejection by Meta alerts the Auris team.
  ALERT_GROUPS = %w[follow_up system].freeze
  # The only variables the engine fills in a system template; anything else
  # would reach the patient as raw {{text}}.
  SYSTEM_VARIABLES = %w[nome dia hora profissional procedimento link].freeze
  VARIABLE_REGEX = /\{\{\s*([^{}\s]+)\s*\}\}/

  module_function

  def templates
    CONFIG['templates']
  end

  def examples
    CONFIG['examples']
  end

  def find(name)
    templates.find { |template| template['name'] == name.to_s }
  end

  def group_of(name)
    find(name)&.dig('group')
  end

  def follow_up
    templates.select { |template| template['group'] == 'follow_up' }
  end

  def alert?(name)
    ALERT_GROUPS.include?(group_of(name))
  end

  def body_variables(text)
    text.to_s.scan(VARIABLE_REGEX).flatten.uniq
  end

  # Meta `/message_templates` payload with NAMED parameters.
  def meta_payload(template)
    components = [body_component(template['body'])]
    components << buttons_component(template['buttons']) if template['buttons'].present?
    { 'name' => template['name'], 'language' => LANGUAGE, 'category' => template['category'],
      'parameter_format' => 'NAMED', 'components' => components }
  end

  def body_component(text)
    component = { 'type' => 'BODY', 'text' => text }
    variables = body_variables(text)
    return component if variables.empty?

    component.merge('example' => {
                      'body_text_named_params' => variables.map { |name| { 'param_name' => name, 'example' => examples.fetch(name, name) } }
                    })
  end

  def buttons_component(buttons)
    { 'type' => 'BUTTONS', 'buttons' => buttons.map { |text| { 'type' => 'QUICK_REPLY', 'text' => text } } }
  end

  # Why a create (payload with name/language), update (payload without them)
  # or delete (no payload) of this template is refused, or nil when allowed.
  # Follow-up templates are only ever installed by the kit; system templates
  # keep the contract the engine relies on.
  def violation(name, payload = nil)
    template = find(name)
    return if template.nil? || template['group'] == 'suggested'
    return I18n.t('errors.meta_templates.kit_reserved') if template['group'] == 'follow_up'
    return if payload.nil?
    return I18n.t('errors.meta_templates.kit_locked_fields') unless locked_fields_kept?(template, payload)

    variables_violation(payload)
  end

  def variables_violation(payload)
    invalid = body_variables(component(payload, 'BODY')&.dig('text')) - SYSTEM_VARIABLES
    return if invalid.empty?

    I18n.t('errors.meta_templates.kit_invalid_variables', variables: invalid.join(', '), allowed: SYSTEM_VARIABLES.join(', '))
  end

  def locked_fields_kept?(template, payload)
    buttons = Array(component(payload, 'BUTTONS')&.dig('buttons')).map { |button| [button['type'].to_s.upcase, button['text']] }
    payload.fetch('language', LANGUAGE) == LANGUAGE && payload['category'].to_s.upcase == template['category'] &&
      buttons == Array(template['buttons']).map { |text| ['QUICK_REPLY', text] }
  end

  def component(payload, type)
    Array(payload['components']).find { |c| c['type'].to_s.upcase == type }
  end

  # The kit as the inbox's settings page shows it: clinic data filled in and,
  # for every template the WABA already has, its id and status.
  def for_inbox(inbox)
    existing = Array(inbox.channel.message_templates).select { |t| t.is_a?(Hash) && t['language'] == LANGUAGE }.index_by { |t| t['name'] }
    templates.map do |template|
      payload = meta_payload(template.merge('body' => fill_clinic_data(template['body'], inbox)))
      payload.merge('group' => template['group'], 'existing_id' => existing.dig(template['name'], 'id'),
                    'existing_status' => existing.dig(template['name'], 'status'))
    end
  end

  # [endereço da clínica] stays for the clinic to fill: there is no address
  # on the account yet.
  def fill_clinic_data(text, inbox)
    text = text.gsub('[nome da clínica]', inbox.account.name)
    hours = Whatsapp::TemplateKit::WorkingHours.text(inbox)
    hours ? text.gsub('[horário de funcionamento]', hours) : text
  end
end
