<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import ContactAppointmentsAPI from 'dashboard/api/contactAppointments';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { formatCurrency } from 'dashboard/routes/dashboard/funnel/funnelFormatters';

const props = defineProps({
  contactId: { type: [String, Number], required: true },
});

const { t } = useI18n();
const { currentAccount } = useAccount();

const appointments = ref([]);
const isLoading = ref(false);

const OPEN_STATUSES = ['scheduled', 'rescheduled', 'confirmed'];
const STATUS_CLASSES = {
  scheduled: 'bg-n-teal-3 text-n-teal-11',
  rescheduled: 'bg-n-teal-3 text-n-teal-11',
  confirmed: 'bg-n-teal-3 text-n-teal-11',
  attended: 'bg-n-blue-3 text-n-blue-11',
  no_show: 'bg-n-amber-3 text-n-amber-11',
  canceled: 'bg-n-ruby-3 text-n-ruby-11',
};

const statusLabels = computed(() => ({
  scheduled: t('CONVERSATION_SIDEBAR.APPOINTMENTS.STATUS.SCHEDULED'),
  rescheduled: t('CONVERSATION_SIDEBAR.APPOINTMENTS.STATUS.RESCHEDULED'),
  confirmed: t('CONVERSATION_SIDEBAR.APPOINTMENTS.STATUS.CONFIRMED'),
  attended: t('CONVERSATION_SIDEBAR.APPOINTMENTS.STATUS.ATTENDED'),
  no_show: t('CONVERSATION_SIDEBAR.APPOINTMENTS.STATUS.NO_SHOW'),
  canceled: t('CONVERSATION_SIDEBAR.APPOINTMENTS.STATUS.CANCELED'),
}));

const locale = computed(() =>
  (currentAccount.value?.locale || 'en').replace('_', '-')
);

const fetchAppointments = async () => {
  if (!props.contactId) return;
  isLoading.value = true;
  try {
    const { data } = await ContactAppointmentsAPI.get(props.contactId);
    appointments.value = data.payload;
  } finally {
    isLoading.value = false;
  }
};

watch(() => props.contactId, fetchAppointments, { immediate: true });

const formatDate = value =>
  new Intl.DateTimeFormat(locale.value, {
    weekday: 'short',
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(value));

// Upcoming open appointments read in green, like on the funnel card.
const isUpcoming = appointment =>
  OPEN_STATUSES.includes(appointment.status) &&
  !!appointment.scheduled_for &&
  new Date(appointment.scheduled_for) > new Date();

const details = appointment =>
  [appointment.professional?.name, appointment.procedure?.name]
    .filter(Boolean)
    .join(' · ');

const formatAmount = amount =>
  amount === null || amount === undefined
    ? ''
    : formatCurrency(amount, currentAccount.value?.locale);
</script>

<template>
  <div class="px-4 pb-4">
    <div v-if="isLoading" class="flex justify-center py-4">
      <Spinner />
    </div>
    <p
      v-else-if="!appointments.length"
      class="py-4 m-0 text-sm text-center text-n-slate-11"
    >
      {{ t('CONVERSATION_SIDEBAR.APPOINTMENTS.EMPTY') }}
    </p>
    <ul v-else class="flex flex-col gap-2 p-0 m-0 list-none">
      <li
        v-for="appointment in appointments"
        :key="appointment.id"
        class="flex flex-col gap-1 px-3 py-2 border rounded-lg border-n-weak"
      >
        <div class="flex items-center justify-between gap-2 min-w-0">
          <span
            class="flex items-center gap-1 min-w-0 text-xs font-semibold"
            :class="
              isUpcoming(appointment) ? 'text-n-teal-11' : 'text-n-slate-12'
            "
          >
            <span class="i-lucide-calendar-check size-3.5 flex-shrink-0" />
            <span class="truncate">
              {{
                appointment.scheduled_for
                  ? formatDate(appointment.scheduled_for)
                  : t('CONVERSATION_SIDEBAR.APPOINTMENTS.NO_DATE')
              }}
            </span>
          </span>
          <span
            class="px-1.5 py-0.5 text-[11px] font-medium rounded flex-shrink-0"
            :class="STATUS_CLASSES[appointment.status]"
          >
            {{ statusLabels[appointment.status] }}
          </span>
        </div>
        <span
          v-if="details(appointment)"
          class="text-xs truncate text-n-slate-11"
          :title="details(appointment)"
        >
          {{ details(appointment) }}
        </span>
        <span
          v-if="appointment.source_name"
          class="text-[11px] text-n-slate-10"
        >
          {{
            t('CONVERSATION_SIDEBAR.APPOINTMENTS.SOURCE', {
              source: appointment.source_name,
            })
          }}
        </span>
        <div
          v-if="appointment.procedures.length"
          class="flex flex-col gap-0.5 pt-1 mt-0.5 border-t border-n-weak"
        >
          <span class="text-[11px] font-medium text-n-slate-11">
            {{ t('CONVERSATION_SIDEBAR.APPOINTMENTS.CLOSED_PROCEDURES') }}
          </span>
          <div
            v-for="(procedure, index) in appointment.procedures"
            :key="index"
            class="flex items-center justify-between gap-2 text-xs"
          >
            <span class="truncate text-n-slate-12">
              {{
                procedure.name ||
                t('CONVERSATION_SIDEBAR.APPOINTMENTS.UNNAMED_PROCEDURE')
              }}
            </span>
            <span class="flex-shrink-0 font-medium text-n-slate-12">
              {{ formatAmount(procedure.amount_paid) }}
            </span>
          </div>
        </div>
      </li>
    </ul>
  </div>
</template>
