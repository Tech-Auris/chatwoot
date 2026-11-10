<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import HomeDrillButton from './HomeDrillButton.vue';
import {
  bucketLabel,
  sparklinePath,
  sparklinePoints,
  variation,
} from '../homeFormatters';

const props = defineProps({
  title: { type: String, required: true },
  // Null while the indicator is not built yet: the card shows a dash.
  metric: { type: Object, default: null },
  // Faltas: fewer is better, so a drop shows in green.
  lowerIsBetter: { type: Boolean, default: false },
  // Explains how the number is counted, behind an ⓘ next to the title.
  info: { type: String, default: '' },
  // Shows the "open details" icon next to the number.
  drillable: { type: Boolean, default: false },
  // A line under the number (e.g. the share of the leads).
  detail: { type: String, default: '' },
  // Start (unix) of each point of the trend line and what a point covers
  // (day, week or month), for the tooltip.
  buckets: { type: Array, default: () => [] },
  granularity: { type: String, default: 'day' },
});

const emit = defineEmits(['drill']);

// One sentence per line, in a narrow balloon. The text is our own copy.
const infoTooltip = computed(() => ({
  content: `<div class="max-w-xs">${props.info.split('\n').join('<br>')}</div>`,
  html: true,
}));

const { t, locale } = useI18n();

const WIDTH = 160;
const HEIGHT = 36;

const delta = computed(() =>
  props.metric ? variation(props.metric.total, props.metric.previous) : null
);

const isGood = computed(() =>
  props.lowerIsBetter ? delta.value < 0 : delta.value > 0
);

const linePath = computed(() =>
  sparklinePath(props.metric?.series || [], WIDTH, HEIGHT)
);
const areaPath = computed(() =>
  linePath.value ? `${linePath.value} L${WIDTH},${HEIGHT} L0,${HEIGHT} Z` : ''
);

const points = computed(() =>
  sparklinePoints(props.metric?.series || [], WIDTH, HEIGHT)
);

// The point under the mouse: nearest along the line.
const hovered = ref(null);
const onHover = event => {
  const series = props.metric?.series || [];
  if (!series.length) return;
  const { left, width } = event.currentTarget.getBoundingClientRect();
  const ratio = Math.min(Math.max((event.clientX - left) / width, 0), 1);
  hovered.value = Math.round(ratio * (series.length - 1));
};

const hoveredPoint = computed(() => {
  if (hovered.value === null) return null;
  const index = hovered.value;
  const { x, y } = points.value[index] || points.value[0];
  const label = bucketLabel(
    props.buckets[index],
    props.buckets[index + 1] || null,
    props.granularity,
    locale.value
  );
  return {
    left: `${(x / WIDTH) * 100}%`,
    top: `${(y / HEIGHT) * 100}%`,
    // Kept inside the card at both ends of the line.
    tooltipLeft: `${Math.min(Math.max((x / WIDTH) * 100, 18), 82)}%`,
    text: `${label}: ${props.metric.series[index]}`,
  };
});

const subtitle = computed(() =>
  props.metric ? props.detail : t('HOME_OVERVIEW.METRICS.COMING_SOON')
);

const deltaTooltip = computed(() =>
  t('HOME_OVERVIEW.METRICS.VS_PREVIOUS', { value: props.metric?.previous })
);
</script>

<template>
  <div
    class="flex flex-col gap-1 px-4 py-3 rounded-xl bg-n-solid-2 outline outline-1 outline-n-container"
  >
    <div class="flex items-center gap-1 text-sm text-n-slate-11">
      {{ title }}
      <span
        v-if="info"
        v-tooltip.top="infoTooltip"
        class="cursor-help i-lucide-info size-3.5 text-n-slate-10"
      />
    </div>
    <div class="flex items-center gap-1.5">
      <span
        class="text-2xl font-semibold"
        :class="metric ? 'text-n-slate-12' : 'text-n-slate-9'"
      >
        {{ metric ? metric.total : '—' }}
      </span>
      <span
        v-if="delta !== null && delta !== 0"
        v-tooltip.top="deltaTooltip"
        class="px-1.5 py-0.5 text-xs font-semibold rounded cursor-default"
        :class="
          isGood ? 'bg-n-teal-3 text-n-teal-11' : 'bg-n-ruby-3 text-n-ruby-11'
        "
      >
        {{ delta > 0 ? '▲' : '▼' }} {{ Math.abs(delta) }}%
      </span>
      <HomeDrillButton
        v-if="drillable && metric?.total"
        @click="emit('drill')"
      />
    </div>
    <div v-if="subtitle" class="text-xs text-n-slate-10">{{ subtitle }}</div>
    <slot />
    <div
      v-if="metric"
      class="relative mt-1 cursor-crosshair"
      @mousemove="onHover"
      @mouseleave="hovered = null"
    >
      <svg
        :viewBox="`0 0 ${WIDTH} ${HEIGHT}`"
        class="block w-full h-9 text-n-brand"
        preserveAspectRatio="none"
      >
        <path :d="areaPath" class="fill-current opacity-10" />
        <path
          :d="linePath"
          class="stroke-current"
          fill="none"
          stroke-width="2"
          vector-effect="non-scaling-stroke"
        />
      </svg>
      <template v-if="hoveredPoint">
        <span
          class="absolute rounded-full pointer-events-none size-2 bg-n-brand -translate-x-1/2 -translate-y-1/2 outline outline-2 outline-n-solid-2"
          :style="{ left: hoveredPoint.left, top: hoveredPoint.top }"
        />
        <div
          class="absolute z-10 px-2 py-1 mb-1 text-xs rounded-md pointer-events-none bottom-full whitespace-nowrap -translate-x-1/2 bg-n-slate-12 text-n-slate-1"
          :style="{ left: hoveredPoint.tooltipLeft }"
        >
          {{ hoveredPoint.text }}
        </div>
      </template>
    </div>
  </div>
</template>
