require 'rails_helper'

RSpec.describe SalesQuote do
  let(:quote) { create(:sales_quote, prospect_phone: '+55 61 98140-2211') }

  describe 'credentials' do
    it 'issues an unguessable public token and a six digit code' do
      expect(quote.public_token.length).to be >= 32
      expect(quote.access_code).to match(/\A\d{6}\z/)
    end

    it 'keeps the last four digits of the prospect phone to check against' do
      expect(quote.verification_phone_last4).to eq('2211')
    end

    it 'never repeats a public token' do
      expect(create(:sales_quote).public_token).not_to eq(quote.public_token)
    end
  end

  describe '#verify_access' do
    # Both halves travel by WhatsApp, but only the phone digits are something a
    # forwarded link does not carry.
    it 'accepts the code together with the right phone digits' do
      expect(quote.verify_access(code: quote.access_code, phone_last4: '2211')).to be true
    end

    it 'refuses the right code with the wrong phone digits' do
      expect(quote.verify_access(code: quote.access_code, phone_last4: '9999')).to be false
    end

    it 'refuses a wrong code' do
      expect(quote.verify_access(code: '000000', phone_last4: '2211')).to be false
    end

    # A proposal created before the phone was known must not turn into an open
    # door: the code alone still has to match.
    it 'falls back to the code alone when no phone was recorded' do
      open_quote = create(:sales_quote, prospect_phone: nil)

      expect(open_quote.verify_access(code: open_quote.access_code, phone_last4: '')).to be true
      expect(open_quote.verify_access(code: '000000', phone_last4: '')).to be false
    end
  end

  describe '#reservation_active?' do
    it 'is active while the reservation date is ahead' do
      expect(create(:sales_quote, reserved_until: 3.days.from_now)).to be_reservation_active
    end

    # An expired reservation does not kill the proposal — it only stops holding
    # the discount, and the page keeps working at full price.
    it 'is over once the date has passed' do
      expect(create(:sales_quote, reserved_until: 1.day.ago)).not_to be_reservation_active
    end

    it 'is not active when no reservation was ever made' do
      expect(quote).not_to be_reservation_active
    end
  end

  describe 'items' do
    it 'keeps the amount that was offered, not the one Stripe has today' do
      item = create(:sales_quote_item, sales_quote: quote, unit_amount: 89_700, quantity: 2)

      expect(item.total_amount).to eq(179_400)
    end
  end
end
