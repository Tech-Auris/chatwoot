<script setup>
import { useI18n } from 'vue-i18n';
import DrillIcon from 'dashboard/routes/dashboard/funnel/components/DrillIcon.vue';

// The "open details" marker next to a card's number, the same icon, size and
// gap as the Conversão do funil chart. No padding: the app pads every button.
const emit = defineEmits(['click']);
const { t } = useI18n();
</script>

<template>
  <button
    type="button"
    class="inline-flex flex-shrink-0 !p-0 text-n-slate-10 hover:text-n-brand"
    :title="t('HOME_OVERVIEW.OPEN_CONVERSATIONS')"
    :aria-label="t('HOME_OVERVIEW.OPEN_CONVERSATIONS')"
    @click="emit('click')"
  >
    <DrillIcon :x="0" :y="0" :size="14" />
  </button>
</template>
