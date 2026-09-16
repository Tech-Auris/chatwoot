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

  describe '.from_meta_messaging' do
    # Real Meta payload for a click-to-Messenger / click-to-IG-DM ad — top-level
    # `messaging.referral` with ad copy under `ads_context_data`. Different
    # from WhatsApp CTWA (no source_url, no ctwa_clid; the ad's opaque token
    # is `ref`).
    let(:ig_ad_messaging) do
      {
        sender: { id: 'IGSID' },
        recipient: { id: 'IG_PAGE_ID' },
        referral: {
          ref: 'AaRDg86i-z5_xrIOfs9Adr1example',
          source: 'ADS',
          type: 'OPEN_THREAD',
          ads_context_data: {
            ad_title: 'Agende sua Consulta',
            photo_url: 'https://scontent.xx.fbcdn.net/thumb.jpg',
            post_id: '17841400000000',
            product_id: nil
          }
        }
      }
    end

    it 'normalizes an Instagram / Messenger ad referral into the shared shape' do
      result = described_class.from_meta_messaging(ig_ad_messaging)

      expect(result).to eq(
        'source_type' => 'ad',
        'source_id' => '17841400000000',
        'ctwa_clid' => 'AaRDg86i-z5_xrIOfs9Adr1example',
        'title' => 'Agende sua Consulta',
        'media_type' => 'image',
        'thumbnail_url' => 'https://scontent.xx.fbcdn.net/thumb.jpg'
      )
    end

    # A referral with source SHORTLINK / CUSTOMER_CHAT_PLUGIN is not an ad —
    # skip it so the operator's Origem stays undecided instead of picking
    # up the wrong attribution.
    it 'returns nil for a non-ad referral source' do
      messaging = ig_ad_messaging.deep_merge(referral: { source: 'SHORTLINK', ads_context_data: nil })
      expect(described_class.from_meta_messaging(messaging)).to be_nil
    end

    it 'returns nil when there is no referral on the messaging object' do
      expect(described_class.from_meta_messaging(sender: { id: 'x' })).to be_nil
    end

    it 'is safe when given nil or a non-hash messaging object' do
      expect(described_class.from_meta_messaging(nil)).to be_nil
      expect(described_class.from_meta_messaging('oops')).to be_nil
    end

    it 'reports video when the ad carries a video_url' do
      messaging = ig_ad_messaging.deep_merge(referral: { ads_context_data: { video_url: 'https://x/vid.mp4', photo_url: nil } })
      expect(described_class.from_meta_messaging(messaging)['media_type']).to eq('video')
    end
  end

  describe '.from_baileys_context_info' do
    # Real payload shape from the wild — Baileys types use camelCase and
    # `mediaType` is a proto enum integer. Some wrappers (Evolution etc.) emit
    # the uppercase string form, so both must normalize to the same shape.
    let(:external_ad_reply) do
      {
        sourceType: 'ad',
        sourceId: '120224217878030096',
        sourceUrl: 'https://fb.me/xyz',
        ctwaClid: 'ARZ.abc123',
        title: 'Agende sua Consulta',
        body: 'Você olha essas veias aparentes?',
        mediaType: 1,
        thumbnailUrl: 'https://scontent.xx.fbcdn.net/thumb.jpg'
      }
    end

    it 'normalizes an externalAdReply payload with numeric mediaType' do
      result = described_class.from_baileys_context_info(externalAdReply: external_ad_reply)

      expect(result).to eq(
        'source_type' => 'ad',
        'source_id' => '120224217878030096',
        'source_url' => 'https://fb.me/xyz',
        'ctwa_clid' => 'ARZ.abc123',
        'title' => 'Agende sua Consulta',
        'body' => 'Você olha essas veias aparentes?',
        'media_type' => 'image',
        'thumbnail_url' => 'https://scontent.xx.fbcdn.net/thumb.jpg'
      )
    end

    it 'downcases a string mediaType (Evolution and other wrappers)' do
      payload = external_ad_reply.merge(mediaType: 'VIDEO')

      expect(described_class.from_baileys_context_info(externalAdReply: payload)['media_type']).to eq('video')
    end

    it 'returns nil when there is no externalAdReply on the contextInfo' do
      expect(described_class.from_baileys_context_info(stanzaId: 'abc')).to be_nil
    end

    it 'returns nil when every field is blank' do
      expect(described_class.from_baileys_context_info(externalAdReply: { sourceId: '' })).to be_nil
    end

    it 'is safe when given nil or a non-hash context_info' do
      expect(described_class.from_baileys_context_info(nil)).to be_nil
      expect(described_class.from_baileys_context_info('oops')).to be_nil
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
