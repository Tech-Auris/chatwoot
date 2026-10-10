require 'rails_helper'

RSpec.describe MarketingIntegration do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
  end

  describe 'validations' do
    subject { create(:marketing_integration) }

    it { is_expected.to validate_uniqueness_of(:account_id).scoped_to(:provider) }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:provider).with_values(meta_capi: 0, google_ads_enhanced: 1) }
    it { is_expected.to define_enum_for(:status).with_values(disabled: 0, test_mode: 1, active: 2) }
  end

  describe 'credentials round-trip' do
    let(:integration) { build(:marketing_integration) }

    it 'serializes and reads back the credentials hash' do
      integration.credentials = { 'pixel_id' => '999', 'access_token' => 'tok' }
      integration.save!
      integration.reload

      expect(integration.credentials).to eq('pixel_id' => '999', 'access_token' => 'tok')
    end

    # An empty ciphertext must not crash the reader — the UI creates rows with
    # nil credentials while the operator is still filling the form.
    it 'returns an empty hash when the ciphertext is blank' do
      integration.credentials_ciphertext = nil
      expect(integration.credentials).to eq({})
    end
  end

  describe 'credential validation' do
    # Only enforced when the integration is live (test_mode or active). A
    # disabled row can sit with empty credentials while the operator drafts.
    # The pixels and their tokens live on `marketing_pixels`; an active Meta
    # integration only carries the optional ads read token.
    it 'accepts an active Meta CAPI integration without credentials' do
      expect(build(:marketing_integration, status: :active, credentials: {})).to be_valid
    end

    it 'reads spend with the ads read token, else the first pixel token' do
      integration = create(:marketing_integration)
      create(:marketing_pixel, marketing_integration: integration, access_token: 'EAAG_first')
      expect(integration.ads_read_access_token).to eq('EAAG_first')

      integration.update!(credentials: { 'ads_read_token' => 'EAAG_read' })
      expect(integration.ads_read_access_token).to eq('EAAG_read')
    end

    it 'requires the Google Ads keys on an active Google integration' do
      integration = build(:marketing_integration, :google_ads, status: :active, credentials: {})
      expect(integration).to be_invalid
      expect(integration.errors[:credentials].first).to include('customer_id', 'conversion_action_id', 'developer_token', 'oauth_refresh_token')
    end

    it 'is valid on a disabled row with empty credentials' do
      integration = build(:marketing_integration, status: :disabled, credentials: {})
      expect(integration).to be_valid
    end
  end
end
