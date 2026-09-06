require 'rails_helper'

RSpec.describe TermsAcceptanceRequest do
  it 'accepts a valid campaign' do
    request = build(:terms_acceptance_request)

    expect(request).to be_valid
  end

  it 'requires document_date and deadline_at' do
    request = build(:terms_acceptance_request, document_date: nil, deadline_at: nil)

    expect(request).not_to be_valid
    expect(request.errors.attribute_names).to include(:document_date, :deadline_at)
  end

  # A deadline too close leaves managers no room to sign; too far away turns
  # into a request nobody remembers.
  describe 'deadline bounds' do
    it 'refuses a deadline sooner than the minimum window' do
      request = build(:terms_acceptance_request, deadline_at: 12.hours.from_now)

      expect(request).not_to be_valid
      expect(request.errors[:deadline_at]).to be_present
    end

    it 'refuses a deadline farther than the maximum window' do
      request = build(:terms_acceptance_request, deadline_at: 100.days.from_now)

      expect(request).not_to be_valid
      expect(request.errors[:deadline_at]).to be_present
    end

    it 'accepts a deadline at the boundary' do
      request = build(:terms_acceptance_request, deadline_at: (described_class::DEADLINE_MAX_DAYS - 1).days.from_now)

      expect(request).to be_valid
    end
  end

  it 'defaults kind to :update in the factory (super_admin campaigns)' do
    expect(build(:terms_acceptance_request).kind).to eq('update')
  end
end
