# The comments the contract step leaves on the deal's ClickUp task: when the
# contract goes out (with the data the customer confirmed) and when the
# customer signs it.
module Sales::ContractClickupComment
  PAYMENT_LABELS = { 'card' => 'Cartão de crédito', 'pix' => 'PIX à vista', 'boleto' => 'Boleto' }.freeze

  module_function

  def generated(contract)
    data = contract.data
    lines = ['📄 *Contrato gerado e enviado para assinatura*', "*Tipo:* #{contract.person_type_pj? ? 'Pessoa Jurídica' : 'Pessoa Física'}"]
    lines += ["*Razão social:* #{data['razao_social']}", "*CNPJ:* #{data['cnpj']}"] if contract.person_type_pj?
    lines += [
      "*#{contract.person_type_pj? ? 'Representante legal' : 'Contratante'}:* #{data['nome']} · CPF #{data['cpf']}",
      "*E-mail:* #{data['email']}", "*WhatsApp:* #{data['whatsapp']}", "*Endereço:* #{data['endereco']}",
      "*Forma de pagamento:* #{payment_label(contract)}", "*Modelo do contrato:* v#{contract.template_version}",
      "*Assinatura da Auris:* #{contract.auris_signed_at ? "automática em #{format_time(contract.auris_signed_at)}" : 'pendente'}"
    ]
    lines << "*Assinar até:* #{format_time(contract.deadline_at)}" if contract.deadline_at
    lines.join("\n")
  end

  def signed(contract)
    ["✅ *Contrato assinado pelo cliente* em #{format_time(contract.signed_at)}", contract.signing_url].compact.join("\n")
  end

  def payment_label(contract)
    label = PAYMENT_LABELS.fetch(contract.payment_method, contract.payment_method)
    contract.installments.to_i > 1 ? "#{label} em #{contract.installments}x" : label
  end

  def format_time(time)
    time.in_time_zone(Sales::ClickupProspectSearchService::SALES_TIMEZONE).strftime('%d/%m/%Y %H:%M')
  end
end
