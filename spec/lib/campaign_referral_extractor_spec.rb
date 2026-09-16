require 'rails_helper'

RSpec.describe CampaignReferralExtractor do
  describe '.from_cloud_message' do
    it 'returns a normalized hash with only the fields Meta filled in' do
      message = {
        referral: {
          source_url: 'https://fb.me/abc',
          source_type: 'ad',
          source_id: '123456789',
          headline: 'Agende sua consulta',
          body: 'Você olha essas veias...',
          media_type: 'image',
          image_url: 'https://scontent.xx.fbcdn.net/thumb.jpg',
          ctwa_clid: 'ARZ.EY2xxx'
        }
      }

      expect(described_class.from_cloud_message(message)).to eq(
        'source_type' => 'ad',
        'source_id' => '123456789',
        'source_url' => 'https://fb.me/abc',
        'ctwa_clid' => 'ARZ.EY2xxx',
        'title' => 'Agende sua consulta',
        'body' => 'Você olha essas veias...',
        'media_type' => 'image',
        'thumbnail_url' => 'https://scontent.xx.fbcdn.net/thumb.jpg'
      )
    end

    it 'accepts a payload with string keys (matches raw webhook parsing)' do
      message = { 'referral' => { 'source_id' => 'abc', 'headline' => 'oi' } }

      expect(described_class.from_cloud_message(message)).to eq(
        'source_id' => 'abc',
        'title' => 'oi'
      )
    end

    # Cloud sends `video_url` or `thumbnail_url` for video ads; fall through to
    # whichever the payload actually filled in.
    it 'falls back to video_url when the ad has no image' do
      message = { referral: { source_id: '1', video_url: 'https://x/video-thumb.mp4', media_type: 'VIDEO' } }

      expect(described_class.from_cloud_message(message)).to include(
        'thumbnail_url' => 'https://x/video-thumb.mp4',
        'media_type' => 'video'
      )
    end

    # Baileys and Cloud non-CTWA inbounds omit the referral block entirely;
    # nil there is the expected shape the callers rely on to skip persistence.
    it 'returns nil when no referral block is present' do
      expect(described_class.from_cloud_message({ from: '5511', text: { body: 'oi' } })).to be_nil
    end

    it 'returns nil when every referral field is blank' do
      expect(described_class.from_cloud_message({ referral: { source_url: '' } })).to be_nil
    end

    it 'is safe when given a non-hash message' do
      expect(described_class.from_cloud_message(nil)).to be_nil
      expect(described_class.from_cloud_message('oi')).to be_nil
    end
  end

  describe '.gclid_from_body' do
    it 'extracts the token from a prefilled WhatsApp message body' do
      body = 'Olá, quero informação sobre a promoção. gclid=Cj0KCQ-abc_123'
      expect(described_class.gclid_from_body(body)).to eq('Cj0KCQ-abc_123')
    end

    it 'returns nil when the body has no gclid' do
      expect(described_class.gclid_from_body('Bom dia, tudo bem?')).to be_nil
    end

    it 'returns nil for blank or nil input' do
      expect(described_class.gclid_from_body(nil)).to be_nil
      expect(described_class.gclid_from_body('')).to be_nil
    end
  end
end
