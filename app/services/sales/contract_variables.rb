# The values that fill the contract template's `{{campos}}`. `sample` feeds the
# Super Admin preview; the real values come from the reservation and the data
# the customer confirms in the Contrato step.
module Sales::ContractVariables
  FIELDS = %w[razao_social cnpj endereco representante_nome representante_cpf representante_email
              nome_completo cpf email periodo_licenca produtos valor_total valor_total_extenso
              forma_pagamento descontos data_contratacao].freeze

  module_function

  # The real values for a proposal, the data the customer confirmed and the
  # payment method they chose.
  def for(quote:, data:, payment_method:)
    data = data.stringify_keys
    contractor(data).merge(
      endereco: data['endereco'],
      periodo_licenca: license_period(quote),
      produtos: products(quote),
      valor_total: money(quote.effective_total_amount),
      valor_total_extenso: Sales::MoneyInWords.call(quote.effective_total_amount),
      forma_pagamento: payment_terms(quote, payment_method),
      descontos: discounts(quote),
      data_contratacao: I18n.l(Date.current, format: '%d/%m/%Y')
    )
  end

  def contractor(data)
    if data['person_type'] == 'pf'
      { nome_completo: data['nome'], cpf: data['cpf'], email: data['email'] }
    else
      { razao_social: data['razao_social'], cnpj: data['cnpj'], representante_nome: data['nome'],
        representante_cpf: data['cpf'], representante_email: data['email'] }
    end
  end

  def license_period(quote)
    months = Sales::CheckoutService::CYCLE_MONTHS[quote.billing_cycle.to_sym]
    "#{months} (#{Sales::MoneyInWords.number(months)}) meses, contados a partir da data de assinatura deste Contrato"
  end

  def products(quote)
    lines = quote.items.map do |item|
      name = ERB::Util.html_escape(item.name)
      item.quantity.to_i > 1 ? "<li>#{name} × #{item.quantity}</li>" : "<li>#{name}</li>"
    end
    "<ul>#{lines.join}</ul>"
  end

  # The installment amount is the total split evenly, as AsaaS charges it.
  def payment_terms(quote, payment_method)
    total = quote.effective_total_amount
    return pix_terms(quote, total) if payment_method.to_s == 'pix'

    count = Sales::CheckoutService.installments_for(quote.billing_cycle)
    parcel = (total / count.to_f).round
    means = payment_method.to_s == 'boleto' ? 'por boleto bancário' : 'no cartão de crédito'
    "#{count} (#{Sales::MoneyInWords.number(count)}) parcelas de R$ #{money(parcel)} (#{Sales::MoneyInWords.call(parcel)}) #{means}"
  end

  def pix_terms(quote, total)
    percent = Sales::CheckoutService.pix_discount_for(quote.billing_cycle)
    amount = total - ((total * percent) / 100.0).round
    text = "à vista, via PIX, no valor de R$ #{money(amount)} (#{Sales::MoneyInWords.call(amount)})"
    percent.positive? ? "#{text}, já com #{percent}% de desconto" : text
  end

  def discounts(quote)
    amount = quote.effective_discount_amount.to_i
    return 'Não há' unless amount.positive?

    summary = quote.effective_discount_summary.presence
    [summary, "R$ #{money(amount)}"].compact.join(' – ')
  end

  def money(cents)
    Sales::ReservationMessageBuilder.format_money(cents)
  end

  def sample(person_type)
    contractor = if person_type.to_s == 'pf'
                   { nome_completo: 'Ana Maria Souza', cpf: '987.654.321-00', email: 'ana@exemplo.com.br' }
                 else
                   { razao_social: 'Clínica Exemplo Serviços Médicos Ltda.', cnpj: '12.345.678/0001-90',
                     representante_nome: 'Gustavo Fraga', representante_cpf: '123.456.789-09',
                     representante_email: 'gustavo@clinicaexemplo.com.br' }
                 end
    contractor.merge(
      endereco: 'Avenida Paulista, 1000, Conj. 101, Bela Vista, São Paulo/SP, CEP 01310-100',
      periodo_licenca: '12 (doze) meses, de 15/10/2026 a 14/10/2027',
      produtos: '<ul><li>Plano Auris</li><li>Profissional adicional × 2</li></ul>',
      valor_total: '22.190,40',
      valor_total_extenso: Sales::MoneyInWords.call(2_219_040),
      forma_pagamento: "12 (doze) parcelas de R$ 1.849,20 (#{Sales::MoneyInWords.call(184_920)}) no cartão de crédito",
      descontos: '10% de desconto na reunião (R$ 2.465,60)',
      data_contratacao: '15/10/2026'
    )
  end
end
