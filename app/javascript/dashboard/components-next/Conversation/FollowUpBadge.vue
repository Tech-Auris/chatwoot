<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// The FUP in progress on a conversation: a ring with one slice per FUP the
// account runs, the sent ones filled, and the current FUP number inside.
const props = defineProps({
  followUp: { type: Object, required: true },
  // `sm` fits the funnel card; `md` is the conversation header.
  size: {
    type: String,
    default: 'sm',
    validator: value => ['sm', 'md'].includes(value),
  },
});

const { t } = useI18n();

const RADIUS = 10;
const CIRCUMFERENCE = 2 * Math.PI * RADIUS;

const total = computed(() => Math.max(props.followUp.total || 1, 1));
const failed = computed(() => props.followUp.delivery_status === 'failed');

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

const delayLabel = minutes => {
  const days = Math.floor(minutes / 1440);
  const hours = Math.floor((minutes % 1440) / 60);
  const rest = minutes % 60;
  if (days) return hours ? `${days}d ${hours}h` : `${days}d`;
  if (hours) return rest ? `${hours}h${rest}min` : `${hours}h`;
  return `${rest}min`;
};

const label = computed(() =>
  t('CONVERSATION.FOLLOW_UP.LABEL', {
    step: props.followUp.step,
    total: total.value,
  })
);

const tooltip = computed(() => {
  if (failed.value) {
    return `${label.value} · ${t('CONVERSATION.FOLLOW_UP.FAILED')}`;
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
</script>

<template>
  <span
    role="img"
    :title="tooltip"
    :aria-label="tooltip"
    class="relative inline-flex flex-shrink-0 items-center justify-center rounded-full"
    :class="[
      size === 'md' ? 'size-7' : 'size-6',
      failed ? 'text-n-ruby-11' : 'text-n-blue-11',
    ]"
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
        :class="failed ? 'stroke-n-ruby-9' : 'stroke-n-blue-9'"
        :stroke-dasharray="doneDash"
        transform="rotate(-88 12 12)"
      />
    </svg>
    <span class="absolute text-[10px] font-bold leading-none">
      {{ followUp.step }}
    </span>
  </span>
</template>
