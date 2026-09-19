<script setup>
import { computed, toRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useConversationWindow } from 'dashboard/composables/useConversationWindow';

// The backend serializes `Conversation#messaging_window`. `null` is a
// legitimate value (non-Cloud channels) — parent decides whether to
// mount us, but guard here anyway so a stale payload doesn't break the
// render.
const props = defineProps({
  window: {
    type: Object,
    default: null,
  },
});

const { t } = useI18n();
const windowRef = toRef(props, 'window');
const { state, clock } = useConversationWindow(windowRef);

// Each state carries its own label and tooltip; keep the dictionary
// close to the render so future edits land in one place.
const label = computed(() => {
  const s = state.value;
  if (!s) return null;
  const key = s.tone === 'warn' ? 'CLOSING' : `LABEL_${s.kind.toUpperCase()}`;
  return t(`CONVERSATION.MESSAGING_WINDOW.${key}`);
});

const tooltip = computed(() => {
  const s = state.value;
  if (!s) return null;
  if (s.expiresAt) {
    const when = new Date(s.expiresAt).toLocaleString();
    return t(`CONVERSATION.MESSAGING_WINDOW.TOOLTIP_${s.kind.toUpperCase()}`, {
      when,
    });
  }
  return t('CONVERSATION.MESSAGING_WINDOW.TOOLTIP_CLOSED');
});

// Every state carries its own explainer text so the atendente can hover
// the "?" and learn what that particular window means without having to
// leave the conversation.
const HINT_KEYS = {
  free: 'HINT_CTWA_72H',
  std: 'HINT_STANDARD_24H',
  warn: 'HINT_CLOSING',
  closed: 'HINT_CLOSED',
};

const hint = computed(() => {
  const key = HINT_KEYS[state.value?.tone];
  return key ? t(`CONVERSATION.MESSAGING_WINDOW.${key}`) : null;
});

// Inline styles instead of Tailwind classes for the tone palette. During
// integration we hit a case where the color classes rendered as an
// outline-only pill (bg swallowed by an upstream rule or missed by the
// Tailwind JIT scan against this file); switching to inline rgba tokens
// bypasses that whole class of problems and keeps the chip readable on
// any panel ground.
const TONE_STYLES = {
  free: {
    backgroundColor: 'rgba(16, 185, 129, 0.22)',
    borderColor: 'rgba(16, 185, 129, 0.45)',
    color: '#065F46',
  },
  std: {
    backgroundColor: 'rgba(37, 99, 235, 0.20)',
    borderColor: 'rgba(37, 99, 235, 0.45)',
    color: '#1E3A8A',
  },
  warn: {
    backgroundColor: 'rgba(217, 119, 6, 0.28)',
    borderColor: 'rgba(217, 119, 6, 0.55)',
    color: '#78350F',
  },
  closed: {
    backgroundColor: 'rgba(220, 38, 38, 0.20)',
    borderColor: 'rgba(220, 38, 38, 0.45)',
    color: '#7F1D1D',
  },
};

const chipStyle = computed(() => TONE_STYLES[state.value?.tone] || {});

// Help "?" badge picks up the chip tone but a shade darker so it reads
// as a distinct element against the pill fill without introducing a new
// color.
const HELP_STYLES = {
  free: { backgroundColor: 'rgba(16, 185, 129, 0.35)', color: '#065F46' },
  std: { backgroundColor: 'rgba(37, 99, 235, 0.32)', color: '#1E3A8A' },
  warn: { backgroundColor: 'rgba(217, 119, 6, 0.40)', color: '#78350F' },
  closed: { backgroundColor: 'rgba(220, 38, 38, 0.30)', color: '#7F1D1D' },
};

const helpStyle = computed(() => HELP_STYLES[state.value?.tone] || {});

// Dot colors follow the tone but stay fully saturated. The warn state
// also pulses to grab the atendente's eye — inline animation so it lands
// regardless of whether Tailwind's `animate-pulse` shipped in this
// build's CSS.
const DOT_COLORS = {
  free: '#10B981',
  std: '#2563EB',
  warn: '#D97706',
  closed: '#DC2626',
};

const dotStyle = computed(() => {
  const tone = state.value?.tone;
  const base = { backgroundColor: DOT_COLORS[tone] || '#94A3B8' };
  if (tone === 'free') {
    base.boxShadow = '0 0 0 3px rgba(16, 185, 129, 0.25)';
  }
  if (tone === 'warn') {
    base.animation = 'auris-window-chip-pulse 1.4s ease-in-out infinite';
  }
  return base;
});
</script>

<template>
  <div
    v-if="state"
    :title="tooltip"
    :style="chipStyle"
    class="inline-flex items-center gap-1.5 pl-2 pr-2 py-1 rounded-full text-xs font-semibold leading-none border transition-colors"
    data-testid="conversation-window-chip"
  >
    <span class="w-1.5 h-1.5 rounded-full flex-none" :style="dotStyle" />
    <span>{{ label }}</span>
    <span
      v-if="clock"
      class="pl-0.5 font-mono font-medium text-[11px] opacity-85 tabular-nums"
    >
      {{ clock }}
    </span>
    <span
      v-if="hint"
      :title="hint"
      :style="helpStyle"
      class="inline-flex items-center justify-center w-4 h-4 rounded-full text-[10px] font-bold cursor-help"
      data-testid="conversation-window-chip-help"
    >
      ?
    </span>
  </div>
</template>

<style>
@keyframes auris-window-chip-pulse {
  0%,
  100% {
    transform: scale(1);
    opacity: 1;
  }
  50% {
    transform: scale(1.35);
    opacity: 0.5;
  }
}
@media (prefers-reduced-motion: reduce) {
  [data-testid='conversation-window-chip']
    > span[style*='auris-window-chip-pulse'] {
    animation: none !important;
  }
}
</style>
