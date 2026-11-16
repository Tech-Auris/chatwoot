import { rememberInbox, rememberedInbox } from '../rememberedInbox';

describe('rememberedInbox', () => {
  beforeEach(() => localStorage.clear());

  it('returns null when nothing was remembered', () => {
    expect(rememberedInbox(1)).toBeNull();
  });

  it('remembers the inbox per account', () => {
    rememberInbox(1, 7);
    rememberInbox(2, 9);
    expect(rememberedInbox(1)).toBe(7);
    expect(rememberedInbox(2)).toBe(9);
  });
});
