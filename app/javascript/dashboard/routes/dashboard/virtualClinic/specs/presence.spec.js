import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount } from '@vue/test-utils';
import { defineComponent, h } from 'vue';
import { useClinicPresence } from '../composables/useClinicPresence';

const perform = vi.fn();
let channel = null;
vi.mock('@rails/actioncable', () => ({
  createConsumer: () => ({
    subscriptions: {
      create: (params, callbacks) => {
        channel = { params, ...callbacks };
        return { perform };
      },
    },
    disconnect: vi.fn(),
  }),
}));

const position = { x: 100, y: 120, direction: 'down', moving: false };
const start = () => {
  let presence;
  mount(
    defineComponent({
      setup() {
        presence = useClinicPresence();
        return () => h('div');
      },
    })
  );
  presence.connect({
    userId: 1,
    accountId: 9,
    pubsubToken: 'token',
    position: () => position,
  });
  return presence;
};
const hear = data =>
  channel.received({ event: 'virtual_clinic.presence', data });

describe('useClinicPresence', () => {
  beforeEach(() => vi.clearAllMocks());

  it('goes quiet when the clinic is opened in another tab, until taken back', () => {
    const presence = start();
    const { session } = channel.params;
    hear({
      user_id: 1,
      session: 'other-tab',
      since: Date.now() + 1000,
      x: 0,
      y: 0,
    });
    expect(presence.passive.value).toBe(true);

    presence.send(position, true);
    expect(perform).not.toHaveBeenCalled();

    presence.takeOver();
    expect(presence.passive.value).toBe(false);
    expect(perform).toHaveBeenCalledWith(
      'move',
      expect.objectContaining({ x: 100 })
    );
    expect(session).toBeTruthy();
  });

  it('keeps following the newest tab of someone else and ignores the older one', () => {
    const presence = start();
    hear({ user_id: 2, session: 'new', since: 2000, x: 146, y: 176 });
    hear({ user_id: 2, session: 'old', since: 1000, x: 52, y: 44 });
    presence.step(1);
    expect(presence.others.value[2]).toMatchObject({ x: 146, y: 176 });

    // The old tab closing doesn't take them off the map.
    hear({ user_id: 2, session: 'old', left: true });
    expect(presence.others.value[2]).toBeDefined();
    hear({ user_id: 2, session: 'new', left: true });
    expect(presence.others.value[2]).toBeUndefined();
  });
});
