<script setup>
import { computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { useI18n } from 'vue-i18n';

import SectionLayout from './SectionLayout.vue';

const { t } = useI18n();
const { currentAccount } = useAccount();

const versionName = computed(
  () =>
    currentAccount.value.secretary_version_name ||
    t('GENERAL_SETTINGS.FORM.SECRETARY.NONE')
);
</script>

<template>
  <SectionLayout
    :title="t('GENERAL_SETTINGS.FORM.SECRETARY.TITLE')"
    :description="t('GENERAL_SETTINGS.FORM.SECRETARY.NOTE')"
    with-border
  >
    <span class="text-sm font-medium text-n-slate-12">{{ versionName }}</span>
  </SectionLayout>
</template>
