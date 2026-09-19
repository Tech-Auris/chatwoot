<script setup>
import { computed, toRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useConversationWindow } from 'dashboard/composables/useConversationWindow';
import Icon from 'next/icon/Icon.vue';

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
  if (!s || !s.expiresAt) {
    return t('CONVERSATION.MESSAGING_WINDOW.TOOLTIP_CLOSED');
  }
  const when = new Date(s.expiresAt).toLocaleString();
  return t(`CONVERSATION.MESSAGING_WINDOW.TOOLTIP_${s.kind.toUpperCase()}`, {
    when,
  });
});
</script>

<template>
  <div
    v-if="state"
    :title="tooltip"
    class="inline-flex items-center gap-2 pl-2 pr-2.5 py-1 rounded-full text-xs font-semibold leading-none border transition-colors"
    :class="[
      {
        'bg-emerald-50 dark:bg-emerald-950/40 text-emerald-700 dark:text-emerald-300 border-emerald-200 dark:border-emerald-800':
          state.tone === 'free',
        'bg-blue-50 dark:bg-blue-950/40 text-blue-700 dark:text-blue-300 border-blue-200 dark:border-blue-800':
          state.tone === 'std',
        'bg-amber-50 dark:bg-amber-950/40 text-amber-700 dark:text-amber-300 border-amber-200 dark:border-amber-800':
          state.tone === 'warn',
        'bg-red-50 dark:bg-red-950/40 text-red-700 dark:text-red-300 border-red-200 dark:border-red-800':
          state.tone === 'closed',
      },
    ]"
    data-testid="conversation-window-chip"
  >
    <span
      class="w-1.5 h-1.5 rounded-full"
      :class="[
        {
          'bg-emerald-500 shadow-[0_0_0_3px_rgba(16,185,129,0.22)]':
            state.tone === 'free',
          'bg-blue-500': state.tone === 'std',
          'bg-amber-500 animate-pulse motion-reduce:animate-none':
            state.tone === 'warn',
          'bg-red-500': state.tone === 'closed',
        },
      ]"
    />
    <span>{{ label }}</span>
    <span
      v-if="clock"
      class="font-mono font-medium text-[11px] opacity-85 tabular-nums"
    >
      {{ clock }}
    </span>
    <Icon
      v-if="state.tone === 'closed'"
      icon="i-lucide-lock"
      class="size-3 opacity-80"
    />
  </div>
</template>
