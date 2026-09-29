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

    'Vendedor criou a reserva. A mensagem abaixo é enviada automaticamente ao cliente pelo WhatsApp comercial ' \
      "(confira o envio no grid de Reservas):\n\n#{message}"
  end

  # Sent on the reservation's last day to a lead who hasn't closed yet.
  # Two wordings: the special condition with the meeting discount (and how
  # much it saves), or a plain follow-up on the quote.
  def self.last_day_reminder_for(quote)
    link = public_url_for(quote)
    return nil if link.blank?

    name = quote.prospect_name.to_s.split.first.presence || 'Olá'
    return discount_reminder(name, link, quote.meeting_discount_amount) if quote.meeting_discount && quote.meeting_discount_amount.to_i.positive?

    <<~MSG
      #{name}, tudo bem?
      Passando para te lembrar que hoje é o último dia da reserva do seu orçamento da Auris, conforme combinamos.

      Você havia ficado de me dar um retorno até hoje sobre a contratação.

      Caso queira avançar, basta acessar o link abaixo e concluir:
      Link: #{link}

      Se precisar de alguma informação antes de finalizar, pode me chamar por aqui.
    MSG
  end

  def self.discount_reminder(name, link, discount_cents)
    <<~MSG
      #{name}, tudo bem?

      Passando para te lembrar que hoje é o último dia da reserva da sua condição especial da Auris com 10% de desconto.

      Você vai economizar R$ #{format_money(discount_cents)} na contratação.
      Para aproveitar o desconto, basta acessar o link abaixo e concluir a contratação:
      Link: #{link}

      A condição fica disponível somente até o final do dia de hoje.
    MSG
  end

  def self.format_money(cents)
    ActiveSupport::NumberHelper.number_to_currency(cents.to_i / 100.0, unit: '', separator: ',', delimiter: '.', precision: 2).strip
  end

  def self.format_deadline(time)
    return '' if time.blank?

    time.strftime('%d/%m/%Y')
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
