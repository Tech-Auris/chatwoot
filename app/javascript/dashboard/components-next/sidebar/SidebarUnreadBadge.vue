<script setup>
import { computed } from 'vue';

const props = defineProps({
  count: { type: [Number, String], default: 0 },
  variant: { type: String, default: 'default' },
});

const normalizedCount = computed(() => {
  const count = Number(props.count);
  return Number.isFinite(count) && count > 0 ? count : 0;
});

const displayCount = computed(() =>
  normalizedCount.value > 99 ? '99+' : String(normalizedCount.value)
);
</script>

<template>
  <span
    v-if="normalizedCount > 0"
    data-test-id="sidebar-unread-badge"
    class="inline-grid h-5 min-w-5 place-items-center rounded-full px-1 text-xxs font-medium leading-3 flex-shrink-0"
    :class="
      variant === 'brand'
        ? 'bg-n-brand text-white'
        : 'bg-n-slate-4 text-n-slate-12 dark:bg-n-slate-5'
    "
  >
    {{ displayCount }}
  </span>
  <span v-else class="hidden" />
</template>
