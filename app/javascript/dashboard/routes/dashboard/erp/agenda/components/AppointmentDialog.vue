<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

// The basic data of one appointment, the same for every ERP (the shape of
// Agenda::Source). Read only.
const props = defineProps({
  locale: { type: String, default: 'en' },
});

const { t } = useI18n();
const dialogRef = ref(null);
const appointment = ref(null);

const formatDate = value =>
  new Intl.DateTimeFormat(props.locale, {
    weekday: 'long',
    day: '2-digit',
    month: 'long',
    year: 'numeric',
  }).format(new Date(value));

const formatTime = value =>
  value
    ? new Intl.DateTimeFormat(props.locale, {
        hour: '2-digit',
        minute: '2-digit',
      }).format(new Date(value))
    : null;

const rows = computed(() => {
  const item = appointment.value;
  if (!item) return [];
  return [
    { key: 'PATIENT', value: item.patient_name },
    { key: 'PROFESSIONAL', value: item.professional_name },
    { key: 'DATE', value: formatDate(item.starts_at) },
    { key: 'STARTS_AT', value: formatTime(item.starts_at) },
    { key: 'ENDS_AT', value: formatTime(item.ends_at) },
    { key: 'PROCEDURE', value: item.procedure_name },
    {
      key: 'STATUS',
      value: t(`AGENDA.STATUS.${item.status.toUpperCase()}`),
    },
  ];
});

const open = item => {
  appointment.value = item;
  dialogRef.value?.open();
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('AGENDA.APPOINTMENT.TITLE')"
    :confirm-button-label="t('AGENDA.APPOINTMENT.CLOSE')"
    :show-cancel-button="false"
    width="md"
    @confirm="dialogRef.close()"
  >
    <dl class="grid grid-cols-[auto_1fr] gap-x-6 gap-y-3 m-0 text-sm">
      <template v-for="row in rows" :key="row.key">
        <dt class="text-n-slate-11">
          {{ t(`AGENDA.APPOINTMENT.${row.key}`) }}
        </dt>
        <dd class="m-0 font-medium first-letter:uppercase text-n-slate-12">
          {{ row.value || '—' }}
        </dd>
      </template>
    </dl>
  </Dialog>
</template>
