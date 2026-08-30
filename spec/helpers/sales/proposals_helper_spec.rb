require 'rails_helper'

# The page is written in Portuguese and read by a customer in Brazil. Rails'
# own helpers answer in the request locale, and this app registers Brazilian
# Portuguese as `pt_BR` while rails-i18n files its formats under `pt-BR` — so
# they fall back to English on a page that has none.
RSpec.describe Sales::ProposalsHelper do
  describe '#proposal_datetime' do
    it 'reads the date the way a brazilian reader does' do
      expect(helper.proposal_datetime(Time.zone.parse('2028-08-31 23:59'))).to eq('31/08/2028 às 23:59')
    end

    it 'has nothing to say about a proposal with no deadline' do
      expect(helper.proposal_datetime(nil)).to be_nil
    end
  end

  describe '#proposal_time_left' do
    it 'counts the days that are left' do
      expect(helper.proposal_time_left(12.days.from_now)).to eq('mais 12 dias')
    end

    it 'says the last day in the singular' do
      expect(helper.proposal_time_left(1.day.from_now)).to eq('mais um dia')
    end

    it 'stops counting on the final day' do
      expect(helper.proposal_time_left(2.hours.from_now)).to eq('menos de um dia')
    end
  end

  describe '#proposal_amount' do
    # "R$3,000.00" can be read as three reais by somebody used to our notation.
    it 'separates thousands and cents the brazilian way' do
      expect(helper.proposal_amount(300_000)).to eq('R$ 3.000,00')
    end

    it 'prints a proposal with no discount as zero' do
      expect(helper.proposal_amount(0)).to eq('R$ 0,00')
    end
  end
end
