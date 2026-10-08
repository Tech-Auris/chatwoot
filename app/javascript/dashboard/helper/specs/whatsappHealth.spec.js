import {
  qualityKey,
  qualityStyle,
  accountStatusDot,
  sendBlockReason,
  campaignWarnings,
} from '../whatsappHealth';

describe('whatsappHealth', () => {
  it('reads a ban from the number status, over the quality rating', () => {
    expect(
      qualityKey({ quality_rating: 'GREEN', phone_status: 'BANNED' })
    ).toBe('BANNED');
    expect(
      qualityKey({ quality_rating: 'YELLOW', phone_status: 'CONNECTED' })
    ).toBe('YELLOW');
    expect(qualityKey({})).toBe('UNKNOWN');
  });

  it('falls back to the neutral style for a rating it does not know', () => {
    expect(qualityStyle('RED').dot).toBe('bg-n-ruby-9');
    expect(qualityStyle('SOMETHING_NEW')).toEqual(qualityStyle('UNKNOWN'));
  });

  it('colors the account status like the health page', () => {
    expect(accountStatusDot('APPROVED')).toBe('bg-n-teal-9');
    expect(accountStatusDot('PENDING')).toBe('bg-n-amber-9');
    expect(accountStatusDot('REJECTED')).toBe('bg-n-ruby-9');
  });

  describe('sendBlockReason', () => {
    const baileys = connection => ({
      channel_type: 'Channel::Whatsapp',
      provider: 'baileys',
      provider_connection: { connection },
    });

    it('lets a connected unofficial number send and stops the others', () => {
      expect(sendBlockReason(baileys('open'))).toBeNull();
      expect(sendBlockReason(baileys('connecting'))).toBe('CONNECTING');
      expect(sendBlockReason(baileys('close'))).toBe('DISCONNECTED');
      expect(sendBlockReason(baileys(undefined))).toBe('DISCONNECTED');
    });

    // Meta has accepted sends while reporting the number as blocked.
    it('never stops an official number, whatever Meta reports', () => {
      const cloud = {
        channel_type: 'Channel::Whatsapp',
        provider: 'whatsapp_cloud',
        provider_connection: {
          health: { phone_status: 'BANNED', can_send_message: 'BLOCKED' },
        },
      };
      expect(sendBlockReason(cloud)).toBeNull();
      expect(sendBlockReason({ channel_type: 'Channel::Email' })).toBeNull();
    });
  });

  describe('campaignWarnings', () => {
    const inbox = health => ({ provider_connection: { health } });

    it('warns about Meta limiting sends and the quality rating', () => {
      const warnings = campaignWarnings(
        inbox({
          can_send_message: 'LIMITED',
          quality_rating: 'RED',
          health_errors: [{ error_description: 'Too many reports' }],
        })
      );

      expect(warnings).toEqual([
        { key: 'LIMITED', details: ['Too many reports'] },
        { key: 'QUALITY_LOW' },
      ]);
    });

    it('warns when the audience is over the daily limit', () => {
      const number = inbox({ messaging_limit_tier: 'TIER_250' });

      expect(campaignWarnings(number, 250)).toEqual([]);
      expect(campaignWarnings(number, 1000)).toEqual([
        { key: 'OVER_DAILY_LIMIT', params: { count: 1000, limit: 250 } },
      ]);
      expect(
        campaignWarnings(inbox({ messaging_limit_tier: 'TIER_UNLIMITED' }), 1e6)
      ).toEqual([]);
    });
  });
});
