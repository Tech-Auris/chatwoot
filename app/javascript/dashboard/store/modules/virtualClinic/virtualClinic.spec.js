import { describe, it, expect } from 'vitest';
import { getters, mutations } from './index';

describe('virtualClinic store', () => {
  it('adds the open alerts to the internal chat unread count for the menu badge', () => {
    const state = { alertCounts: {} };
    mutations.SET_ALERT_COUNTS(state, { secretary: 2, manager: 1 });

    expect(getters.getAlertCounts(state)).toEqual({ secretary: 2, manager: 1 });
    expect(
      getters.getMenuBadge(state, {}, {}, { 'internalChat/getUnreadCount': 4 })
    ).toBe(7);
  });

  it('clears the counts', () => {
    const state = { alertCounts: { secretary: 2 } };
    mutations.SET_ALERT_COUNTS(state, null);
    expect(getters.getMenuBadge(state, {}, {}, {})).toBe(0);
  });
});
