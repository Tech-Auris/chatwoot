require 'rails_helper'
require Rails.root.join('db/migrate/20261010120000_create_marketing_pixels.rb')

# The pixel each account had before multi-pixel moves into `marketing_pixels`
# on deploy, so conversions keep firing to it.
RSpec.describe CreateMarketingPixels do
  let(:account) { create(:account) }
  let(:integration) { create(:marketing_integration, account: account) }
  let!(:dispatch) { create(:conversion_event_dispatch, account: account) }

  before do
    integration.update!(status: :test_mode,
                        credentials: { 'pixel_id' => '999888', 'access_token' => 'EAAG_old', 'test_event_code' => 'TEST1',
                                       'ads_read_token' => 'EAAG_read' })
    migration = described_class.new
    migration.verbose = false
    migration.send(:move_existing_pixels)
  end

  it 'turns the old pixel into the first pixel with the same status and token' do
    expect(integration.pixels.sole).to have_attributes(name: 'Pixel principal', pixel_id: '999888', access_token: 'EAAG_old',
                                                       test_event_code: 'TEST1', status: 'test_mode')
  end

  it 'leaves the ads read token on the integration, now active for the ad accounts' do
    expect(integration.reload).to have_attributes(status: 'active', credentials: { 'ads_read_token' => 'EAAG_read' })
  end

  it 'ties the Meta dispatches so far to that pixel' do
    expect(dispatch.reload.marketing_pixel_id).to eq(integration.pixels.sole.id)
  end
end
