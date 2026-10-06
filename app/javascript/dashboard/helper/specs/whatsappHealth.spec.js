import { qualityKey, qualityStyle, accountStatusDot } from '../whatsappHealth';

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
});
