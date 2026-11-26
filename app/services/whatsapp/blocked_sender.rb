# The one rule every WhatsApp inbound path applies to a blocked contact (Cloud, Baileys,
# Z-API and the coexistence history import): what the contact sends is not filed, so it
# opens no conversation and reaches no bot, webhook or automation, while the echo of a
# reply typed on the business phone is still filed, or the agent's own answer would go
# missing from the thread. Taking a reaction back is not a new message: the paths
# reconcile it before asking this.
module Whatsapp::BlockedSender
  module_function

  def silenced?(contact, from_me:)
    contact.blocked? && !from_me
  end
end
