<script setup>
// A card with one value already formatted (a duration, a percentage) and its
// change against the previous period, in % or in percentage points.
const props = defineProps({
  title: { type: String, required: true },
  value: { type: String, required: true },
  // Signed change; null hides the badge.
  delta: { type: Number, default: null },
  deltaUnit: { type: String, default: '%' },
  lowerIsBetter: { type: Boolean, default: false },
  detail: { type: String, default: '' },
  // The previous period's value, already formatted, for the badge tooltip.
  previousLabel: { type: String, default: '' },
});

const isGood = () => (props.lowerIsBetter ? props.delta < 0 : props.delta > 0);
</script>

<template>
  <div
    class="flex flex-col gap-1 px-4 py-3 rounded-xl bg-n-solid-2 outline outline-1 outline-n-container"
  >
    <div class="text-sm text-n-slate-11">{{ title }}</div>
    <div class="flex items-center gap-2">
      <span class="text-2xl font-semibold text-n-slate-12">{{ value }}</span>
      <span
        v-if="delta"
        v-tooltip.top="
          $t('HOME_OVERVIEW.METRICS.VS_PREVIOUS', { value: previousLabel })
        "
        class="px-1.5 py-0.5 text-xs font-semibold rounded cursor-default"
        :class="
          isGood() ? 'bg-n-teal-3 text-n-teal-11' : 'bg-n-ruby-3 text-n-ruby-11'
        "
      >
        {{ delta > 0 ? '▲' : '▼' }} {{ Math.abs(delta) }} {{ deltaUnit }}
      </span>
    </div>
    <div v-if="detail" class="text-xs text-n-slate-10">{{ detail }}</div>
  </div>
</template>
