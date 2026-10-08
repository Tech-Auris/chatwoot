import {
  qualityKey,
  qualityStyle,
  accountStatusDot,
  sendBlockReason,
  sendWarningReason,
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
    const cloud = health => ({
      channel_type: 'Channel::Whatsapp',
      provider: 'whatsapp_cloud',
      provider_connection: { health },
    });

    it('lets a connected unofficial number send and stops the others', () => {
      expect(sendBlockReason(baileys('open'))).toBeNull();
      expect(sendBlockReason(baileys('connecting'))).toBe('CONNECTING');
      expect(sendBlockReason(baileys('close'))).toBe('DISCONNECTED');
      expect(sendBlockReason(baileys(undefined))).toBe('DISCONNECTED');
    });

    it('warns about an official number that is banned, off or restricted', () => {
      expect(sendWarningReason(cloud({ phone_status: 'BANNED' }))).toBe(
        'BANNED'
      );
      expect(sendWarningReason(cloud({ phone_status: 'DISCONNECTED' }))).toBe(
        'NUMBER_DISCONNECTED'
      );
      expect(sendWarningReason(cloud({ phone_status: 'RESTRICTED' }))).toBe(
        'RESTRICTED'
      );
      expect(
        sendWarningReason(
          cloud({ phone_status: 'CONNECTED', can_send_message: 'BLOCKED' })
        )
      ).toBe('META_BLOCKED');
    });

    it('lets a restricted number reply in an open conversation', () => {
      const restricted = cloud({ phone_status: 'RESTRICTED' });

      expect(sendWarningReason(restricted)).toBe('RESTRICTED');
      expect(
        sendWarningReason(restricted, { startsConversation: false })
      ).toBeNull();
    });

    // Meta has accepted sends while reporting the number as blocked.
    it('never stops an official number, whatever Meta reports', () => {
      expect(
        sendBlockReason(
          cloud({ phone_status: 'BANNED', can_send_message: 'BLOCKED' })
        )
      ).toBeNull();
    });

    it('lets low quality, a flagged number and an unread number send', () => {
      expect(
        sendBlockReason(
          cloud({ phone_status: 'CONNECTED', quality_rating: 'RED' })
        )
      ).toBeNull();
      expect(sendBlockReason(cloud({ phone_status: 'FLAGGED' }))).toBeNull();
      // A rejected account review can sit on a number that sends normally.
      expect(
        sendBlockReason(
          cloud({
            phone_status: 'CONNECTED',
            account_review_status: 'REJECTED',
            can_send_message: 'AVAILABLE',
          })
        )
      ).toBeNull();
      expect(
        sendBlockReason(cloud({ can_send_message: 'LIMITED' }))
      ).toBeNull();
      expect(sendBlockReason(cloud(undefined))).toBeNull();
      expect(sendBlockReason({ channel_type: 'Channel::Email' })).toBeNull();
    });
  });
});
