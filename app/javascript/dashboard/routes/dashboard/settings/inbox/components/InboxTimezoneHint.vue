<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { timeZoneOptions } from '../helpers/businessHour';

// The inbox timezone the hours of a tab follow, with a shortcut to the
// "Configurações" tab, where it is changed.
const props = defineProps({
  timezone: { type: String, default: '' },
  text: { type: String, default: '' },
});

defineEmits(['change']);

const { t } = useI18n();

const timezoneLabel = computed(
  () =>
    timeZoneOptions().find(option => option.value === props.timezone)?.label ||
    props.timezone
);
</script>

<template>
  <div class="flex flex-wrap items-center gap-2">
    <span class="text-body-main text-n-slate-11">
      {{ text }}
      {{ t('INBOX_MGMT.TIMEZONE.CURRENT', { timezone: timezoneLabel }) }}
    </span>
    <NextButton
      :label="t('INBOX_MGMT.TIMEZONE.CHANGE')"
      icon="i-lucide-globe"
      slate
      faded
      xs
      @click="$emit('change')"
    />
  </div>
</template>
