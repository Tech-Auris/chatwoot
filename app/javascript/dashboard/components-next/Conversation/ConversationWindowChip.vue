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
  // Where the "?" icon points on a closed window. Parent already computes
  // this for the reply-window banner (per-channel Chatwoot docs URL); we
  // reuse the same link so the atendente lands on the same explainer.
  helpUrl: {
    type: String,
    default: '',
  },
  helpLabel: {
    type: String,
    default: '',
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
  const parts = [];
  if (s.expiresAt) {
    const when = new Date(s.expiresAt).toLocaleString();
    parts.push(
      t(`CONVERSATION.MESSAGING_WINDOW.TOOLTIP_${s.kind.toUpperCase()}`, {
        when,
      })
    );
  } else {
    parts.push(t('CONVERSATION.MESSAGING_WINDOW.TOOLTIP_CLOSED'));
  }
  // On the closed state we surface the docs link inline in the tooltip so
  // the "?" icon has something to reveal on hover / focus.
  if (s.tone === 'closed' && props.helpLabel) {
    parts.push(props.helpLabel);
  }
  return parts.join(' — ');
});

const showHelp = computed(
  () => state.value?.tone === 'closed' && Boolean(props.helpUrl)
);
</script>

<template>
  <div
    v-if="state"
    :title="tooltip"
    class="inline-flex items-center gap-1.5 pl-2 pr-2 py-1 rounded-full text-xs font-semibold leading-none border transition-colors"
    :class="[
      {
        'bg-emerald-100 dark:bg-emerald-950/50 text-emerald-800 dark:text-emerald-300 border-emerald-300 dark:border-emerald-800':
          state.tone === 'free',
        'bg-blue-100 dark:bg-blue-950/50 text-blue-800 dark:text-blue-300 border-blue-300 dark:border-blue-800':
          state.tone === 'std',
        'bg-amber-100 dark:bg-amber-950/50 text-amber-800 dark:text-amber-300 border-amber-300 dark:border-amber-800':
          state.tone === 'warn',
        'bg-red-100 dark:bg-red-950/50 text-red-800 dark:text-red-300 border-red-300 dark:border-red-800':
          state.tone === 'closed',
      },
    ]"
    data-testid="conversation-window-chip"
  >
    <span
      class="w-1.5 h-1.5 rounded-full"
      :class="[
        {
          'bg-emerald-500 shadow-[0_0_0_3px_rgba(16,185,129,0.25)]':
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
      class="pl-0.5 font-mono font-medium text-[11px] opacity-85 tabular-nums"
    >
      {{ clock }}
    </span>
    <Icon
      v-if="state.tone === 'closed' && !showHelp"
      icon="i-lucide-lock"
      class="size-3 opacity-80"
    />
    <a
      v-if="showHelp"
      :href="helpUrl"
      target="_blank"
      rel="noopener noreferrer"
      :title="helpLabel"
      class="inline-flex items-center justify-center w-4 h-4 rounded-full text-[10px] font-bold no-underline focus:outline-none focus-visible:ring-2 focus-visible:ring-red-400 bg-red-200 dark:bg-red-900/60 text-red-800 dark:text-red-200 hover:bg-red-300 dark:hover:bg-red-900"
      data-testid="conversation-window-chip-help"
      @click.stop
    >
      ?
    </a>
  </div>
</template>
