# The two WhatsApp signals that a patient does not want marketing: Meta
# refusing a template because they stopped the business's marketing messages,
# and a click on the template's own opt-out quick-reply button. Either one
# turns the contact's marketing opt-out on.
module Whatsapp::MarketingOptOut
  # "This message was not delivered to maintain healthy ecosystem engagement":
  # the user chose to stop marketing messages from this business.
  ERROR_CODE = 131_050

  # Quick-reply texts that mean "stop", matched whole (case aside), so a
  # button like "Sair da fila" does not count.
  BUTTON_TEXTS = ['Não quero receber', 'Parar de receber', 'Sair'].freeze

  module_function

  def refused_by_meta!(message, error_code)
    return unless error_code.to_i == ERROR_CODE

    message.conversation&.contact&.opt_out!(source: 'meta')
  end

  def button?(*texts)
    texts.compact.any? { |text| BUTTON_TEXTS.any? { |stop| stop.casecmp?(text.to_s.strip) } }
  end
end
