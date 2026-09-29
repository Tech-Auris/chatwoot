require 'rails_helper'

RSpec.describe Sales::ReservationMessageBuilder do
  describe '.last_day_reminder_for' do
    let(:quote) { create(:sales_quote, prospect_name: 'Fernanda Alarcon', reserved_until: 1.hour.from_now) }

    it 'reminds of the 10% condition and how much it saves when the meeting discount applies' do
      quote.update!(meeting_discount: true, meeting_discount_amount: 139_500)

      message = described_class.last_day_reminder_for(quote)

      expect(message).to start_with('Fernanda, tudo bem?')
      expect(message).to include('10% de desconto', 'R$ 1.395,00', described_class.public_url_for(quote))
    end

    it 'follows up on the quote without mentioning a discount otherwise' do
      message = described_class.last_day_reminder_for(quote)

      expect(message).to include('último dia da reserva do seu orçamento', described_class.public_url_for(quote))
      expect(message).not_to include('desconto')
    end
  end
end
