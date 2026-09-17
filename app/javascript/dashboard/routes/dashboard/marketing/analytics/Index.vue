<script setup>
// Placeholder for the Marketing Analytics report. The real page ships in
// Fase 3 · F3 (backend builder + rich grid with cost / CPL / ROAS
// aggregated per campaign/ad). Kept as a stub so the sidebar entry from
// F1 doesn't dangle.
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
</script>

<template>
  <div
    class="flex flex-col items-center justify-center gap-2 p-10 w-full text-center"
  >
    <span class="i-lucide-chart-line text-4xl text-n-slate-11" />
    <h1 class="text-lg font-medium text-n-slate-12">
      {{ t('MARKETING_ANALYTICS_REPORT.TITLE') }}
    </h1>
    <p class="text-sm text-n-slate-11 max-w-md">
      {{ t('MARKETING_ANALYTICS_REPORT.COMING_SOON') }}
    </p>
  </div>
</template>
