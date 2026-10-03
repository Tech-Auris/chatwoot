require 'rails_helper'

RSpec.describe Sales::ContractClickupComment do
  let(:contract) do
    create(:sales_contract, payment_method: 'card', installments: 12, auris_signed_at: Time.zone.parse('2026-10-03 13:00 UTC'),
                            signed_at: Time.zone.parse('2026-10-04 15:30 UTC'))
  end

  it 'lists the data the customer confirmed when the contract goes out' do
    text = described_class.generated(contract)

    expect(text).to include('Contrato gerado e enviado para assinatura', '*Tipo:* Pessoa Jurídica', '*Razão social:* Clínica Cinco Ltda',
                            '*Representante legal:* Maria Souza · CPF 529.982.247-25', '*Forma de pagamento:* Cartão de crédito em 12x',
                            '*Assinatura da Auris:* automática em 03/10/2026 10:00')
  end

  it 'says when the customer signed' do
    expect(described_class.signed(contract)).to include('Contrato assinado pelo cliente* em 04/10/2026 12:30')
  end
end
