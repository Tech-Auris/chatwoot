import { ref } from 'vue';
import { createApp } from 'vue';
import { useConversationWindow } from '../useConversationWindow';

// The composable registers `onBeforeUnmount` for its polling interval,
// which needs an active component instance. Wrap the call in a throwaway
// app so we can exercise it as a real setup — otherwise Vue warns and
// the cleanup never runs after the test.
function runInSetup(fn) {
  let result;
  const app = createApp({
    setup() {
      result = fn();
      return () => null;
    },
  });
  app.mount(document.createElement('div'));
  return [result, app];
}

describe('useConversationWindow', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('returns null when the payload is missing (non-Cloud channel)', () => {
    const source = ref(null);
    const [{ state, clock }, app] = runInSetup(() =>
      useConversationWindow(source)
    );

    expect(state.value).toBeNull();
    expect(clock.value).toBeNull();
    app.unmount();
  });

  it('reports a free tone with countdown for an active CTWA window', () => {
    vi.setSystemTime(new Date('2026-09-19T10:00:00Z'));
    const source = ref({
      kind: 'ctwa_72h',
      opened_at: '2026-09-18T22:00:00Z',
      expires_at: '2026-09-21T22:00:00Z', // 60h ahead
    });
    const [{ state, clock }, app] = runInSetup(() =>
      useConversationWindow(source)
    );

    expect(state.value.kind).toBe('ctwa_72h');
    expect(state.value.tone).toBe('free');
    // 60h → HH:MM display kicks in above 1h.
    expect(clock.value).toBe('60:00');
    app.unmount();
  });

  it('flips to warn tone when a 24h window is closing', () => {
    vi.setSystemTime(new Date('2026-09-19T10:00:00Z'));
    const source = ref({
      kind: 'standard_24h',
      opened_at: '2026-09-18T10:10:00Z',
      expires_at: '2026-09-19T10:10:00Z', // 10 minutes ahead
    });
    const [{ state, clock }, app] = runInSetup(() =>
      useConversationWindow(source)
    );

    // Under 15 min for the standard 24h window → warn tone, MM:SS clock.
    expect(state.value.tone).toBe('warn');
    expect(clock.value).toBe('10:00');
    app.unmount();
  });

  it('reports closed with no clock when the window has expired', () => {
    vi.setSystemTime(new Date('2026-09-19T10:00:00Z'));
    const source = ref({
      kind: 'standard_24h',
      opened_at: '2026-09-18T05:00:00Z',
      expires_at: '2026-09-19T05:00:00Z', // Already past.
    });
    const [{ state, clock }, app] = runInSetup(() =>
      useConversationWindow(source)
    );

    expect(state.value.kind).toBe('closed');
    expect(clock.value).toBeNull();
    app.unmount();
  });

  it('reports the closed kind straight from the payload', () => {
    const source = ref({ kind: 'closed', opened_at: null, expires_at: null });
    const [{ state, clock }, app] = runInSetup(() =>
      useConversationWindow(source)
    );

    expect(state.value.kind).toBe('closed');
    expect(state.value.tone).toBe('closed');
    expect(clock.value).toBeNull();
    app.unmount();
  });
});
