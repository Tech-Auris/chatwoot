<script setup>
import { useI18n } from 'vue-i18n';
import IntegrationsSection from './IntegrationsSection.vue';
import ConversionEventsSection from './ConversionEventsSection.vue';

const { t } = useI18n();
</script>

<template>
  <div class="flex flex-col gap-6 p-6 w-full max-w-4xl mx-auto">
    <header class="flex flex-col gap-1">
      <h1 class="text-lg font-medium text-n-slate-12">
        {{ t('MARKETING_ANALYTICS.TITLE') }}
      </h1>
      <p class="text-sm text-n-slate-11">
        {{ t('MARKETING_ANALYTICS.DESCRIPTION') }}
      </p>
    </header>

    <IntegrationsSection />
    <ConversionEventsSection />
  </div>
</template>
