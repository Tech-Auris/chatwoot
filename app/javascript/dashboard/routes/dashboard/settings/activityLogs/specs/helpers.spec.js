import { FILTERED, formatValue, typeKey } from '../helpers';

describe('activity log helpers', () => {
  it('turns namespaced types into i18n-safe keys', () => {
    expect(typeKey('Integrations::Hook')).toBe('Integrations_Hook');
    expect(typeKey('Contact')).toBe('Contact');
  });

  it('formats empty, object and plain values', () => {
    expect(formatValue(null)).toBe('—');
    expect(formatValue('')).toBe('—');
    expect(formatValue(false)).toBe('false');
    expect(formatValue({ city: 'SP' })).toBe('{"city":"SP"}');
    expect(formatValue(FILTERED)).toBe('[FILTERED]');
  });
});
