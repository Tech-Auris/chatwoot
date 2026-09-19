import { computed, onBeforeUnmount, ref } from 'vue';

function pad(value) {
  return value.toString().padStart(2, '0');
}

// `HH:MM` when at least an hour is left, `MM:SS` under an hour — the
// shorter format kicks in when the atendente needs to see seconds
// ticking (the "fechando" state).
function formatClock(remainingMs) {
  const totalSeconds = Math.floor(remainingMs / 1000);
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;

  if (hours >= 1) {
    return `${pad(hours)}:${pad(minutes)}`;
  }
  return `${pad(minutes)}:${pad(seconds)}`;
}

// Poll the wall clock every 30s so the countdown re-derives without
// waiting for a Cable update — the backend only pushes when the
// conversation itself changes, and the chip needs to tick down between
// events.
const TICK_MS = 30_000;

// Below these thresholds the chip flips to the "warn" tone and starts
// pulsing. The atendente should still be able to answer for free within
// this margin; the point is to make the closing edge visible before it
// arrives.
const WARN_THRESHOLD_MS = {
  ctwa_72h: 30 * 60 * 1000,
  standard_24h: 15 * 60 * 1000,
};

// Reactive view over the `messaging_window` payload the backend attaches
// to every conversation broadcast. The countdown recomputes on tick and
// on every payload update — no need for the caller to reason about the
// wall clock.
//
// Consumer: `<ConversationWindowChip>`.
export function useConversationWindow(windowRef) {
  const now = ref(Date.now());
  const timerId = setInterval(() => {
    now.value = Date.now();
  }, TICK_MS);

  onBeforeUnmount(() => clearInterval(timerId));

  const state = computed(() => {
    const w = windowRef.value;
    if (!w || !w.kind) return null;

    if (w.kind === 'closed') {
      return {
        kind: 'closed',
        remainingMs: 0,
        tone: 'closed',
        expiresAt: null,
      };
    }

    const expiresAt = new Date(w.expires_at).getTime();
    const remainingMs = Math.max(0, expiresAt - now.value);
    if (remainingMs === 0) {
      return {
        kind: 'closed',
        remainingMs: 0,
        tone: 'closed',
        expiresAt: null,
      };
    }

    const warnAt = WARN_THRESHOLD_MS[w.kind] ?? 0;
    let tone;
    if (remainingMs <= warnAt) {
      tone = 'warn';
    } else if (w.kind === 'ctwa_72h') {
      tone = 'free';
    } else {
      tone = 'std';
    }

    return { kind: w.kind, remainingMs, tone, expiresAt };
  });

  const clock = computed(() => {
    const s = state.value;
    if (!s || s.remainingMs === 0) return null;
    return formatClock(s.remainingMs);
  });

  return { state, clock };
}

// `HH:MM` when at least an hour is left, `MM:SS` under an hour — the
// shorter format kicks in when the atendente needs to see seconds ticking
// (the "fechando" state).
