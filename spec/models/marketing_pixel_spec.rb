require 'rails_helper'

RSpec.describe MarketingPixel do
  it 'needs a name, a numeric pixel id and a token' do
    pixel = build(:marketing_pixel, name: ' ', pixel_id: 'abc', access_token: nil)

    expect(pixel).not_to be_valid
    expect(pixel.errors.messages.values.flatten).to include(
      I18n.t('errors.marketing_pixel.name_blank'), I18n.t('errors.marketing_pixel.invalid_id'), I18n.t('errors.marketing_pixel.token_blank')
    )
  end

  it 'sends the test event code only while in test mode' do
    pixel = build(:marketing_pixel, test_event_code: 'TEST1', status: :test_mode)
    expect(pixel.send_as_test?).to be(true)

    pixel.status = :active
    expect(pixel.send_as_test?).to be(false)
  end

  it 'lists as sending only the pixels in test mode or active' do
    integration = create(:marketing_integration)
    sending = [create(:marketing_pixel, marketing_integration: integration, status: :test_mode),
               create(:marketing_pixel, marketing_integration: integration, status: :active)]
    create(:marketing_pixel, marketing_integration: integration, status: :disabled)

    expect(described_class.sending).to match_array(sending)
  end
end
