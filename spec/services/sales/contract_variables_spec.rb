require 'rails_helper'

RSpec.describe Sales::ContractVariables do
  let(:quote) { create(:sales_quote, billing_cycle: :annual, total_amount: 1_395_000) }

  def payment_terms(method)
    described_class.for(quote: quote, data: {}, payment_method: method)[:forma_pagamento]
  end

  it 'states the recurring card as monthly recurring charges' do
    expect(payment_terms('card_recurring'))
      .to eq('12 (doze) cobranças mensais e recorrentes de R$ 1.162,50 (mil cento e sessenta e dois reais e cinquenta centavos) ' \
             'no cartão de crédito')
  end

  it 'keeps the instalments for the card' do
    expect(payment_terms('card')).to start_with('12 (doze) parcelas de R$ 1.162,50')
  end
end
