<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { addDays, format, isSameDay, parseISO, startOfWeek } from 'date-fns';
import { useAccount } from 'dashboard/composables/useAccount';
import AgendaAPI from 'dashboard/api/agenda';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import AgendaGrid from './components/AgendaGrid.vue';

// ERP → Agenda: the clinic's agenda read live from its ERP or calendar, by day
// (a column per professional) or by week (a column per day). Read only.
const { t } = useI18n();
const { currentAccount } = useAccount();

const toInputDate = date => format(date, 'yyyy-MM-dd');

const view = ref('day');
const date = ref(toInputDate(new Date()));
const professionalId = ref('');

const professionals = ref([]);
const appointments = ref([]);
const loading = ref(false);
const error = ref(null);

const locale = computed(() =>
  (currentAccount.value?.locale || 'en').replace('_', '-')
);
const selectedDate = computed(() => parseISO(date.value));
const weekDays = computed(() => {
  const monday = startOfWeek(selectedDate.value, { weekStartsOn: 1 });
  return Array.from({ length: 7 }, (_, i) => addDays(monday, i));
});
const period = computed(() =>
  view.value === 'day'
    ? { from: date.value, to: date.value }
    : {
        from: toInputDate(weekDays.value[0]),
        to: toInputDate(weekDays.value[6]),
      }
);

// A source that couldn't fill everything in one go (patient names looked up
// one by one) answers `complete: false`; asking again fills in the rest.
const MAX_FILL_REQUESTS = 10;

let requestId = 0;
const fetchAgenda = async () => {
  if (!date.value) return;
  requestId += 1;
  const current = requestId;
  loading.value = true;
  error.value = null;
  try {
    for (let attempt = 0; attempt < MAX_FILL_REQUESTS; attempt += 1) {
      // eslint-disable-next-line no-await-in-loop
      const { data } = await AgendaAPI.fetch(period.value);
      if (current !== requestId) return;
      professionals.value = data.professionals;
      appointments.value = data.appointments;
      if (data.complete !== false) break;
    }
  } catch (e) {
    if (current !== requestId) return;
    appointments.value = [];
    error.value = e.response?.data?.error || t('AGENDA.ERROR');
  } finally {
    if (current === requestId) loading.value = false;
  }
};

watch(period, fetchAgenda, { immediate: true, deep: true });

// Professionals from the ERP, plus any that only show up in an appointment.
const professionalOptions = computed(() => {
  const options = new Map(professionals.value.map(p => [String(p.id), p.name]));
  appointments.value.forEach(a => {
    if (a.professional_id && !options.has(String(a.professional_id))) {
      options.set(String(a.professional_id), a.professional_name);
    }
  });
  return [...options]
    .map(([id, name]) => ({ id, name: name || id }))
    .sort((a, b) => a.name.localeCompare(b.name, locale.value));
});

const filteredAppointments = computed(() =>
  professionalId.value
    ? appointments.value.filter(
        a => String(a.professional_id) === professionalId.value
      )
    : appointments.value
);

const nameOf = id =>
  professionalOptions.value.find(p => p.id === id)?.name || id;

const dayColumns = computed(() => {
  const ids = professionalId.value
    ? [professionalId.value]
    : [
        ...new Set(
          filteredAppointments.value.map(a => String(a.professional_id))
        ),
      ];
  return ids
    .map(id => ({
      key: id,
      label: nameOf(id),
      appointments: filteredAppointments.value.filter(
        a => String(a.professional_id) === id
      ),
    }))
    .sort((a, b) => a.label.localeCompare(b.label, locale.value));
});

const dayLabel = day =>
  new Intl.DateTimeFormat(locale.value, {
    weekday: 'short',
    day: '2-digit',
    month: '2-digit',
  }).format(day);

const weekColumns = computed(() =>
  weekDays.value.map(day => ({
    key: toInputDate(day),
    label: dayLabel(day),
    appointments: filteredAppointments.value.filter(a =>
      isSameDay(parseISO(a.starts_at), day)
    ),
  }))
);

const columns = computed(() =>
  view.value === 'day' ? dayColumns.value : weekColumns.value
);
const isEmpty = computed(
  () => !loading.value && !error.value && !filteredAppointments.value.length
);

const shiftDate = direction => {
  const days = view.value === 'day' ? 1 : 7;
  date.value = toInputDate(addDays(selectedDate.value, direction * days));
};
const goToday = () => {
  date.value = toInputDate(new Date());
};

const periodTitle = computed(() => {
  const formatter = new Intl.DateTimeFormat(locale.value, {
    weekday: view.value === 'day' ? 'long' : undefined,
    day: '2-digit',
    month: 'long',
    year: 'numeric',
  });
  if (view.value === 'day') return formatter.format(selectedDate.value);
  return `${dayLabel(weekDays.value[0])} – ${dayLabel(weekDays.value[6])}`;
});

const CONTROL_CLASS =
  '!mb-0 h-8 bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg px-3 text-sm text-n-slate-12 focus:outline-n-brand';
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-solid-1">
    <div class="px-6 pt-5 pb-4 border-b border-n-weak">
      <h1 class="m-0 text-2xl font-semibold leading-tight text-n-slate-12">
        {{ t('AGENDA.TITLE') }}
      </h1>
      <p class="mt-1 mb-4 text-sm text-n-slate-11">
        {{ t('AGENDA.SUBTITLE') }}
      </p>
      <div class="flex flex-wrap items-center gap-3">
        <div
          class="flex p-0.5 rounded-lg bg-n-alpha-black2 outline outline-1 outline-n-weak"
        >
          <button
            v-for="option in ['day', 'week']"
            :key="option"
            type="button"
            class="h-7 px-3 text-sm rounded-md text-n-slate-11"
            :class="{
              'bg-n-solid-1 text-n-slate-12 font-medium shadow-sm':
                view === option,
            }"
            @click="view = option"
          >
            {{ t(`AGENDA.VIEW.${option.toUpperCase()}`) }}
          </button>
        </div>
        <div class="flex items-center gap-1">
          <Button
            icon="i-lucide-chevron-left"
            variant="ghost"
            color="slate"
            size="sm"
            :aria-label="t('AGENDA.PREVIOUS')"
            @click="shiftDate(-1)"
          />
          <Button
            :label="t('AGENDA.TODAY')"
            variant="outline"
            color="slate"
            size="sm"
            @click="goToday"
          />
          <Button
            icon="i-lucide-chevron-right"
            variant="ghost"
            color="slate"
            size="sm"
            :aria-label="t('AGENDA.NEXT')"
            @click="shiftDate(1)"
          />
        </div>
        <input
          v-model="date"
          type="date"
          :aria-label="t('AGENDA.DATE')"
          :class="CONTROL_CLASS"
        />
        <select
          v-model="professionalId"
          :aria-label="t('AGENDA.PROFESSIONAL')"
          :class="CONTROL_CLASS"
          class="pr-9 min-w-56"
        >
          <option value="">{{ t('AGENDA.ALL_PROFESSIONALS') }}</option>
          <option
            v-for="option in professionalOptions"
            :key="option.id"
            :value="option.id"
          >
            {{ option.name }}
          </option>
        </select>
        <span class="text-sm font-medium capitalize text-n-slate-12">
          {{ periodTitle }}
        </span>
        <Spinner v-if="loading" class="size-4 text-n-slate-10" />
      </div>
    </div>

    <div
      v-if="error"
      class="px-4 py-3 mx-6 mt-4 text-sm rounded-lg bg-n-ruby-3 text-n-ruby-12"
    >
      {{ error }}
    </div>
    <p
      v-else-if="isEmpty && view === 'day'"
      class="px-6 py-10 text-sm text-center text-n-slate-11"
    >
      {{ t('AGENDA.EMPTY_DAY') }}
    </p>
    <div
      v-else-if="!(loading && !appointments.length)"
      class="flex-1 overflow-auto"
    >
      <AgendaGrid
        :columns="columns"
        :show-professional="view === 'week' && !professionalId"
        :locale="locale"
      />
    </div>
  </div>
</template>
