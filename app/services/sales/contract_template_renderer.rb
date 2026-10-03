# Fills a contract template: `{{campo}}` takes the escaped value, and
# `{{#se_pj}}…{{/se_pj}}` / `{{#se_pf}}…{{/se_pf}}` keep only the block of the
# person type the contract is for. `produtos` is HTML we build ourselves.
class Sales::ContractTemplateRenderer
  HTML_FIELDS = %w[produtos].freeze
  BLOCK = %r{\{\{#se_(pj|pf)\}\}(.*?)\{\{/se_\1\}\}}m
  FIELD = /\{\{\s*([a-z_]+)\s*\}\}/

  def initialize(content:, variables:, person_type:)
    @content = content
    @variables = variables.stringify_keys
    @person_type = person_type.to_s
  end

  def render
    @content.gsub(BLOCK) { Regexp.last_match(1) == @person_type ? Regexp.last_match(2) : '' }
            .gsub(FIELD) { field(Regexp.last_match(1), Regexp.last_match(0)) }
  end

  private

  def field(name, placeholder)
    return placeholder unless @variables.key?(name)

    value = @variables[name].to_s
    HTML_FIELDS.include?(name) ? value : ERB::Util.html_escape(value)
  end
end
