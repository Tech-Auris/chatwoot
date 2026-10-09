<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import FollowUpHistoryDialog from './FollowUpHistoryDialog.vue';
import { delayLabel } from './followUpFormatters';

// The conversation's FUP: a ring with one slice per FUP the account runs,
// the sent ones filled and the current FUP number inside. Blue while a FUP
// waits for the patient, red when its message did not go out, amber when the
// sequence ended without an answer. Clicking opens every FUP it got.
const props = defineProps({
  conversationId: { type: Number, required: true },
  followUp: { type: Object, required: true },
  // `sm` fits the funnel card; `md` is the conversation header.
  size: {
    type: String,
    default: 'sm',
    validator: value => ['sm', 'md'].includes(value),
  },
});

const { t } = useI18n();
const historyRef = ref(null);

const RADIUS = 10;
const CIRCUMFERENCE = 2 * Math.PI * RADIUS;

const STATES = {
  running: { text: 'text-n-blue-11', stroke: 'stroke-n-blue-9' },
  failed: { text: 'text-n-ruby-11', stroke: 'stroke-n-ruby-9' },
  ended: { text: 'text-n-amber-11', stroke: 'stroke-n-amber-9' },
};

const state = computed(() => props.followUp.state || 'running');
const colors = computed(() => STATES[state.value] || STATES.running);
const total = computed(() => Math.max(props.followUp.total || 1, 1));

const segment = computed(() => {
  const gap = total.value > 1 ? 2.6 : 0;
  return { length: CIRCUMFERENCE / total.value - gap, gap };
});

const trackDash = computed(
  () => `${segment.value.length} ${segment.value.gap}`
);

const doneDash = computed(() => {
  const parts = [];
  for (let i = 0; i < props.followUp.step; i += 1) {
    parts.push(segment.value.length, segment.value.gap);
  }
  return [...parts, 0, CIRCUMFERENCE].join(' ');
});

const label = computed(() =>
  t('CONVERSATION.FOLLOW_UP.LABEL', {
    step: props.followUp.step,
    total: total.value,
  })
);

const tooltip = computed(() => {
  if (state.value === 'failed') {
    return `${label.value} · ${t('CONVERSATION.FOLLOW_UP.FAILED')}`;
  }
  if (state.value === 'ended') {
    return `${label.value} · ${t('CONVERSATION.FOLLOW_UP.ENDED')}`;
  }
  const sentAt = new Date(props.followUp.created_at * 1000).toLocaleString(
    undefined,
    { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }
  );
  return `${label.value} · ${t('CONVERSATION.FOLLOW_UP.SENT_AT', {
    time: sentAt,
    delay: delayLabel(props.followUp.delay_minutes),
  })}`;
});

const openHistory = () => historyRef.value?.open();
</script>

<template>
  <!-- A span, not a button: the global button styles reshape the ring. -->
  <span
    role="button"
    tabindex="0"
    :title="tooltip"
    :aria-label="tooltip"
    class="relative inline-flex flex-shrink-0 items-center justify-center rounded-full cursor-pointer transition-opacity hover:opacity-80"
    :class="[size === 'md' ? 'size-7' : 'size-6', colors.text]"
    @click.stop.prevent="openHistory"
    @keydown.enter.prevent="openHistory"
  >
    <svg class="size-full" viewBox="0 0 24 24" aria-hidden="true">
      <circle
        cx="12"
        cy="12"
        :r="RADIUS"
        fill="none"
        stroke-width="2.4"
        class="stroke-n-slate-6"
        :stroke-dasharray="trackDash"
        transform="rotate(-88 12 12)"
      />
      <circle
        cx="12"
        cy="12"
        :r="RADIUS"
        fill="none"
        stroke-width="2.4"
        :class="colors.stroke"
        :stroke-dasharray="doneDash"
        transform="rotate(-88 12 12)"
      />
    </svg>
    <span class="absolute text-[10px] font-bold leading-none">
      {{ followUp.step }}
    </span>
    <FollowUpHistoryDialog ref="historyRef" :conversation-id="conversationId" />
  </span>
</template>
