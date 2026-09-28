<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import DrillIcon from './DrillIcon.vue';

const props = defineProps({
  reasons: {
    type: Array,
    required: true,
  },
});

// `drill` carries the clicked reason, or null for the total in the middle.
const emit = defineEmits(['drill']);

// Fixed palette cycled by reason index. LossReason has no color column, so a
// deterministic palette keeps colors stable across renders without growing the
// schema. Order picked to read well at small sizes (no near-neighbors).
const PALETTE = [
  '#f59e0b', // amber
  '#3b82f6', // blue
  '#10b981', // emerald
  '#ef4444', // red
  '#8b5cf6', // violet
  '#ec4899', // pink
  '#14b8a6', // teal
  '#f97316', // orange
  '#6366f1', // indigo
  '#84cc16', // lime
];
const colorFor = idx => PALETTE[idx % PALETTE.length];

const total = computed(() =>
  props.reasons.reduce((sum, r) => sum + (r.count || 0), 0)
);

const VIEWBOX = 200;
const RADIUS = 80;
const INNER_RADIUS = 56;
const CENTER = VIEWBOX / 2;

const polar = (radius, angle) => ({
  x: CENTER + radius * Math.sin(angle),
  y: CENTER - radius * Math.cos(angle),
});

const slicePath = (startAngle, endAngle) => {
  const largeArc = endAngle - startAngle > Math.PI ? 1 : 0;
  const outerStart = polar(RADIUS, startAngle);
  const outerEnd = polar(RADIUS, endAngle);
  const innerEnd = polar(INNER_RADIUS, endAngle);
  const innerStart = polar(INNER_RADIUS, startAngle);
  return [
    `M ${outerStart.x.toFixed(2)} ${outerStart.y.toFixed(2)}`,
    `A ${RADIUS} ${RADIUS} 0 ${largeArc} 1 ${outerEnd.x.toFixed(2)} ${outerEnd.y.toFixed(2)}`,
    `L ${innerEnd.x.toFixed(2)} ${innerEnd.y.toFixed(2)}`,
    `A ${INNER_RADIUS} ${INNER_RADIUS} 0 ${largeArc} 0 ${innerStart.x.toFixed(2)} ${innerStart.y.toFixed(2)}`,
    'Z',
  ].join(' ');
};

const fullRingPath = () => {
  // Two half-circles glued back into a ring shape. Avoids the start==end-point
  // degeneracy of trying to draw a single 360° arc.
  const top = polar(RADIUS, 0);
  const bottom = polar(RADIUS, Math.PI);
  const innerBottom = polar(INNER_RADIUS, Math.PI);
  const innerTop = polar(INNER_RADIUS, 0);
  return [
    `M ${top.x.toFixed(2)} ${top.y.toFixed(2)}`,
    `A ${RADIUS} ${RADIUS} 0 0 1 ${bottom.x.toFixed(2)} ${bottom.y.toFixed(2)}`,
    `A ${RADIUS} ${RADIUS} 0 0 1 ${top.x.toFixed(2)} ${top.y.toFixed(2)}`,
    `M ${innerTop.x.toFixed(2)} ${innerTop.y.toFixed(2)}`,
    `A ${INNER_RADIUS} ${INNER_RADIUS} 0 0 0 ${innerBottom.x.toFixed(2)} ${innerBottom.y.toFixed(2)}`,
    `A ${INNER_RADIUS} ${INNER_RADIUS} 0 0 0 ${innerTop.x.toFixed(2)} ${innerTop.y.toFixed(2)}`,
    'Z',
  ].join(' ');
};

// Convert each reason into an SVG path string (donut slice). When there's a
// single slice covering 100%, the standard arc math collapses (start==end
// point) so we render a full ring with two half-arcs instead.
const slices = computed(() => {
  const items = props.reasons.filter(r => (r.count || 0) > 0);
  if (items.length === 0 || total.value === 0) return [];

  if (items.length === 1) {
    return [
      {
        key: items[0].id ?? items[0].name,
        d: fullRingPath(),
        color: colorFor(0),
      },
    ];
  }

  let cumulative = 0;
  return items.map((reason, idx) => {
    const fraction = reason.count / total.value;
    const startAngle = cumulative * 2 * Math.PI;
    const endAngle = (cumulative + fraction) * 2 * Math.PI;
    cumulative += fraction;
    return {
      key: reason.id ?? reason.name,
      d: slicePath(startAngle, endAngle),
      color: colorFor(idx),
    };
  });
});

const legendRows = computed(() =>
  props.reasons
    .filter(r => (r.count || 0) > 0)
    .map((reason, idx) => ({
      key: reason.id ?? reason.name,
      reason,
      color: colorFor(idx),
      name: reason.name,
      count: reason.count,
      percentage: reason.percentage,
    }))
);

const formatCount = value => Number(value || 0).toLocaleString();

// Drill-down icon right after the centered total, placed off its measured width.
const DRILL_ICON_SIZE = 14;
const totalEl = ref(null);
const totalWidth = ref(0);
watch(
  total,
  () =>
    nextTick(() => {
      totalWidth.value = totalEl.value?.getComputedTextLength() || 0;
    }),
  { immediate: true }
);
const formatPct = value => `${Number(value || 0).toFixed(1)}%`;
</script>

<template>
  <div class="flex flex-col items-center gap-4">
    <svg
      :viewBox="`0 0 ${VIEWBOX} ${VIEWBOX}`"
      class="w-full max-w-[220px] h-auto"
      role="img"
      :aria-label="
        $t('FUNNEL_CONVERSION_REPORTS.LOSS_REASONS.CHART_ARIA_LABEL')
      "
    >
      <path
        v-for="slice in slices"
        :key="slice.key"
        :d="slice.d"
        :fill="slice.color"
      />
      <g class="group cursor-pointer" @click="emit('drill', null)">
        <text
          ref="totalEl"
          :x="CENTER"
          :y="CENTER - 4"
          text-anchor="middle"
          class="fill-n-slate-12 text-2xl font-semibold group-hover:fill-n-brand"
        >
          {{ formatCount(total) }}
        </text>
        <DrillIcon
          :x="CENTER + totalWidth / 2 + 5"
          :y="CENTER - 4 - DRILL_ICON_SIZE - 2"
          :size="DRILL_ICON_SIZE"
          class="text-n-slate-10 group-hover:text-n-brand"
        />
      </g>
      <text
        :x="CENTER"
        :y="CENTER + 16"
        text-anchor="middle"
        class="fill-n-slate-11 text-xs"
      >
        {{ $t('FUNNEL_CONVERSION_REPORTS.LOSS_REASONS.CENTER_LABEL') }}
      </text>
    </svg>

    <div class="w-full">
      <div
        class="grid grid-cols-[1.25rem_1fr_auto_auto] gap-x-3 gap-y-2 text-xs text-n-slate-11 items-center"
      >
        <div />
        <div class="font-medium text-n-slate-11 uppercase tracking-wide">
          {{ $t('FUNNEL_CONVERSION_REPORTS.LOSS_REASONS.COLUMN_NAME') }}
        </div>
        <div
          class="font-medium text-n-slate-11 uppercase tracking-wide text-right"
        >
          {{ $t('FUNNEL_CONVERSION_REPORTS.LOSS_REASONS.COLUMN_COUNT') }}
        </div>
        <div
          class="font-medium text-n-slate-11 uppercase tracking-wide text-right"
        >
          {{ $t('FUNNEL_CONVERSION_REPORTS.LOSS_REASONS.COLUMN_PERCENT') }}
        </div>

        <template v-for="row in legendRows" :key="row.key">
          <span
            class="w-3 h-3 rounded-sm justify-self-center"
            :style="{ backgroundColor: row.color }"
          />
          <span class="text-n-slate-12 truncate">{{ row.name }}</span>
          <button
            type="button"
            class="group inline-flex items-center justify-end gap-1 text-n-slate-12 hover:text-n-brand"
            @click="emit('drill', row.reason)"
          >
            {{ formatCount(row.count) }}
            <Icon
              icon="i-lucide-external-link"
              class="size-3 text-n-slate-10 group-hover:text-n-brand"
            />
          </button>
          <span class="text-n-slate-11 text-right">{{
            formatPct(row.percentage)
          }}</span>
        </template>
      </div>
    </div>
  </div>
</template>
