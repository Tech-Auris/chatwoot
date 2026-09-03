# Composes the WhatsApp message the sales team pastes into the
# prospect's chat once the proposal has been reserved. The wording is
# frozen alongside the JS helper at
# `app/javascript/superadmin_pages/helpers/commercialMessage.js` so
# what the seller copies from the panel matches what lands on the
# ClickUp task as a reference comment.
class Sales::ReservationMessageBuilder
  # Reads the same three slots the JS helper reads: link, code and
  # deadline. Returns nil when any of them is missing — the "reservada
  # até X" sentence only reads right with an X.
  def self.for_quote(quote)
    return nil if quote.blank?
    return nil if quote.reserved_until.blank? || quote.access_code.blank?

    link = public_url_for(quote)
    return nil if link.blank?

    <<~MSG
      Olá! 😊

      Conforme alinhado em nossa reunião, você tem uma *condição especial de contratação da Auris com 10% de desconto*.

      Para *reservar essa condição*, é necessário realizar a reserva pelo link abaixo, informar o *código de acesso* e preencher os dados solicitados:

      *Link para reserva:* #{link}
      *Código de acesso:* #{quote.access_code}

      Após o preenchimento, sua condição comercial ficará reservada até *#{format_deadline(quote.reserved_until)}*.

      Se tiver qualquer dúvida durante o preenchimento, pode me chamar por aqui. 💙
    MSG
  end

  # The ClickUp comment wraps the same message with a short instruction
  # heading so whoever reads the task knows what to do with the block —
  # the same person who reserved may not be the one who sends the
  # WhatsApp handoff.
  def self.clickup_comment_for(quote)
    message = for_quote(quote)
    return nil if message.blank?

    "Vendedor criou a reserva. Envie a seguinte mensagem para o cliente:\n\n#{message}"
  end

  def self.format_deadline(time)
    return '' if time.blank?

    "#{time.strftime('%d/%m/%Y')} às #{time.strftime('%H:%M')}"
  end

  # Services do not carry a `request`, so URL helpers need the host
  # passed explicitly. Same pattern the controllers use.
  def self.public_url_for(quote)
    Rails.application.routes.url_helpers.sales_proposal_url(
      quote.public_token,
      host: ENV.fetch('FRONTEND_URL', nil).presence || Rails.application.default_url_options[:host]
    )
  rescue ArgumentError
    nil
  end
end
