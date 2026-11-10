require 'rails_helper'

RSpec.describe Sales::ReservationMessageBuilder do
  describe '.last_day_reminder_for' do
    let(:quote) { create(:sales_quote, prospect_name: 'Fernanda Alarcon', reserved_until: 1.hour.from_now) }

    it 'reminds of the 10% condition and how much it saves on a proposal from before configurable discounts' do
      quote.update!(meeting_discount: true, meeting_discount_amount: 139_500)

      message = described_class.last_day_reminder_for(quote)

      expect(message).to start_with('Fernanda, tudo bem?')
      expect(message).to include('condição especial da Auris (10% reunião)', 'R$ 1.395,00', described_class.public_url_for(quote))
    end

    it 'names the discounts that end with the reservation' do
      quote.update!(meeting_discount: true, meeting_discount_amount: 139_500,
                    applied_discounts: [{ label: '10% reunião', expires_with_reservation: true },
                                        { label: '5% indicação', expires_with_reservation: false }])

      expect(described_class.last_day_reminder_for(quote)).to include('condição especial da Auris (10% reunião).')
    end

    it 'follows up on the quote without mentioning a discount otherwise' do
      message = described_class.last_day_reminder_for(quote)

      expect(message).to include('último dia da reserva do seu orçamento', described_class.public_url_for(quote))
      expect(message).not_to include('desconto')
    end
  end

  describe '.for_quote' do
    let(:quote) { create(:sales_quote, reserved_until: 2.days.from_now) }

    it 'lists the discounts the proposal carries' do
      quote.update!(discount_summary: 'isenção implantação + 10% reunião + 5% indicação')

      expect(described_class.for_quote(quote))
        .to include('*condição especial de contratação da Auris* (isenção implantação, 10% reunião e 5% indicação).')
    end

    it 'does not mention a discount the proposal does not have' do
      message = described_class.for_quote(quote)

      expect(message).to include('*condição especial de contratação da Auris*.')
      expect(message).not_to include('desconto')
    end
  end
end
