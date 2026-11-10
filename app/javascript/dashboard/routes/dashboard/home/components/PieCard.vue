<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import HomeDrillButton from './HomeDrillButton.vue';

const props = defineProps({
  title: { type: String, required: true },
  // [{ label, count }]
  slices: { type: Array, required: true },
});

// The total in the middle opens the conversations behind the chart, like the
// Motivos de perda donut of Funil → Conversão.
const emit = defineEmits(['drill']);

const { t } = useI18n();

const PALETTE = [
  '#3b82f6',
  '#10b981',
  '#6366f1',
  '#f59e0b',
  '#ef4444',
  '#ec4899',
  '#14b8a6',
  '#f97316',
  '#84cc16',
  '#94a3b8',
];

const RADIUS = 50;
const INNER = 36;
const CENTER = 60;

const total = computed(() =>
  props.slices.reduce((sum, slice) => sum + slice.count, 0)
);

const point = (radius, angle) =>
  `${(CENTER + radius * Math.sin(angle)).toFixed(2)} ${(CENTER - radius * Math.cos(angle)).toFixed(2)}`;

const arc = (start, end) => {
  const large = end - start > Math.PI ? 1 : 0;
  return [
    `M ${point(RADIUS, start)}`,
    `A ${RADIUS} ${RADIUS} 0 ${large} 1 ${point(RADIUS, end)}`,
    `L ${point(INNER, end)}`,
    `A ${INNER} ${INNER} 0 ${large} 0 ${point(INNER, start)}`,
    'Z',
  ].join(' ');
};

const rows = computed(() => {
  let angle = 0;
  return props.slices.map((slice, index) => {
    const share = total.value ? slice.count / total.value : 0;
    // A full circle can't be drawn as one arc; stop just short of it.
    const end = angle + Math.min(share, 0.9999) * 2 * Math.PI;
    const row = {
      ...slice,
      color: PALETTE[index % PALETTE.length],
      percent: Math.round(share * 100),
      path: arc(angle, end),
    };
    angle = end;
    return row;
  });
});
</script>

<template>
  <div
    class="flex flex-col gap-3 px-4 py-3 rounded-xl bg-n-solid-2 outline outline-1 outline-n-container"
  >
    <div class="text-sm font-medium text-n-slate-12">{{ title }}</div>
    <p v-if="!total" class="text-sm text-n-slate-10">
      {{ t('HOME_OVERVIEW.METRICS.EMPTY') }}
    </p>
    <div v-else class="flex items-center gap-4">
      <div class="relative flex-shrink-0 size-36">
        <svg viewBox="0 0 120 120" class="size-full">
          <path
            v-for="row in rows"
            :key="row.label"
            :d="row.path"
            :fill="row.color"
          />
        </svg>
        <div class="absolute inset-0 flex flex-col items-center justify-center">
          <div class="flex items-center gap-1">
            <span class="text-xl font-semibold text-n-slate-12">
              {{ total }}
            </span>
            <HomeDrillButton @click="emit('drill')" />
          </div>
          <span class="text-xs text-n-slate-11">
            {{ t('HOME_OVERVIEW.METRICS.TOTAL') }}
          </span>
        </div>
      </div>
      <ul class="flex flex-col flex-1 min-w-0 gap-1 text-xs">
        <li
          v-for="row in rows"
          :key="row.label"
          class="flex items-center gap-2"
        >
          <span
            class="flex-shrink-0 rounded-sm size-2.5"
            :style="{ backgroundColor: row.color }"
          />
          <span class="truncate text-n-slate-12">{{ row.label }}</span>
          <span class="ml-auto text-n-slate-11">{{ row.percent }}%</span>
        </li>
      </ul>
    </div>
  </div>
</template>
