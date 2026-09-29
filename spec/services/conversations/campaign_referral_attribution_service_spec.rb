require 'rails_helper'

RSpec.describe Conversations::CampaignReferralAttributionService do
  let(:conversation) { create(:conversation) }
  let(:form_referral) do
    { 'source_type' => 'website_form', 'source_id' => '120241645998560300', 'title' => 'Agatha', 'fbclid' => 'IwZX',
      'captured_at' => '1790596623', 'ctwa_clid' => 'not-allowed', 'unknown' => 'x' }
  end

  it 'records the allowed keys on a conversation without a referral' do
    expect(described_class.new(conversation: conversation, referral: form_referral).perform).to be(true)

    expect(conversation.reload.additional_attributes['campaign_referral']).to eq(
      'source_type' => 'website_form', 'source_id' => '120241645998560300', 'title' => 'Agatha',
      'fbclid' => 'IwZX', 'captured_at' => 1_790_596_623
    )
  end

  it 'keeps the first referral (first touch wins)' do
    conversation.update!(additional_attributes: { 'campaign_referral' => { 'ctwa_clid' => 'CTWA', 'source_id' => 'AD_1' } })

    expect(described_class.new(conversation: conversation, referral: form_referral).perform).to be(false)
    expect(conversation.reload.additional_attributes['campaign_referral']).to eq('ctwa_clid' => 'CTWA', 'source_id' => 'AD_1')
  end

  it 'keeps the other additional attributes' do
    conversation.update!(additional_attributes: { 'browser' => 'Chrome' })

    described_class.new(conversation: conversation, referral: form_referral).perform

    expect(conversation.reload.additional_attributes['browser']).to eq('Chrome')
  end
end
