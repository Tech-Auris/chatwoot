<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

// The basic data of one appointment, the same for every ERP (the shape of
// Agenda::Source). Read only.
const props = defineProps({
  locale: { type: String, default: 'en' },
});

const { t } = useI18n();
const route = useRoute();
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

const conversationRoute = computed(() => ({
  name: 'inbox_conversation',
  params: {
    accountId: route.params.accountId,
    conversation_id: appointment.value?.auris_conversation_id,
  },
}));

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
    <div
      v-if="appointment?.auris_conversation_id"
      class="flex items-center justify-between gap-3 p-3 mt-4 rounded-lg bg-n-alpha-1"
    >
      <span class="flex items-center gap-2 text-sm text-n-slate-12">
        <span
          class="px-1.5 text-xs font-semibold leading-5 text-white rounded bg-n-brand"
        >
          {{ t('AGENDA.AURIS.BADGE') }}
        </span>
        {{ t('AGENDA.AURIS.BOOKED') }}
      </span>
      <router-link :to="conversationRoute">
        <Button
          :label="t('AGENDA.AURIS.OPEN_CONVERSATION')"
          icon="i-lucide-message-circle"
          variant="link"
          size="sm"
        />
      </router-link>
    </div>
  </Dialog>
</template>
