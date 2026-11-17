<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { addDays, format, parseISO } from 'date-fns';
import { getUnixStartOfDay, getUnixEndOfDay } from 'helpers/DateHelper';
import { useAccount } from 'dashboard/composables/useAccount';
import ReportHeader from './components/ReportHeader.vue';
import AppointmentReportsAPI from 'dashboard/api/appointmentReports';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';

const route = useRoute();
const { t } = useI18n();
const { currentAccount } = useAccount();

// Appointments look ahead, so the shortcuts start today and go forward.
const PRESETS = { today: 0, tomorrow: 1, next7: 7, next30: 30 };
const toInputDate = date => format(date, 'yyyy-MM-dd');

const preset = ref('next30');
const fromDate = ref(toInputDate(new Date()));
const toDate = ref(toInputDate(addDays(new Date(), 30)));
const professional = ref('');
const erpSourceId = ref('');

const rows = ref([]);
const filterOptions = ref({ professionals: [], erp_sources: [] });
const currentPage = ref(1);
const meta = ref({ current_page: 1, per_page: 50, total_count: 0 });
const loading = ref(false);
const error = ref(null);

const accountId = computed(() => route.params.accountId);
const locale = computed(() =>
  (currentAccount.value?.locale || 'en').replace('_', '-')
);
const conversationUrl = row =>
  `/app/accounts/${accountId.value}/conversations/${row.conversation_id}`;

const fetchData = async (page = 1) => {
  currentPage.value = page;
  loading.value = true;
  error.value = null;
  try {
    const { data } = await AppointmentReportsAPI.fetch({
      from: getUnixStartOfDay(parseISO(fromDate.value)),
      to: getUnixEndOfDay(parseISO(toDate.value)),
      professional: professional.value,
      erpSourceId: erpSourceId.value,
      page,
    });
    rows.value = data.rows;
    filterOptions.value = data.filters;
    meta.value = data.meta;
  } catch (e) {
    error.value =
      e.response?.data?.error || e.response?.statusText || e.message;
  } finally {
    loading.value = false;
  }
};

const applyPreset = () => {
  const today = new Date();
  const days = PRESETS[preset.value];
  fromDate.value = toInputDate(
    preset.value === 'tomorrow' ? addDays(today, 1) : today
  );
  toDate.value = toInputDate(addDays(today, days));
  fetchData();
};

const onDateChange = () => {
  if (!fromDate.value || !toDate.value) return;
  preset.value = 'custom';
  fetchData();
};

onMounted(() => fetchData());

const formatDate = value =>
  new Intl.DateTimeFormat(locale.value, {
    weekday: 'short',
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(value));

const STATUS_CLASS = {
  scheduled: 'bg-n-teal-3 text-n-teal-11',
  rescheduled: 'bg-n-amber-3 text-n-amber-11',
  confirmed: 'bg-n-blue-3 text-n-blue-11',
};

const statusLabels = computed(() => ({
  scheduled: t('CONVERSATION_SIDEBAR.APPOINTMENTS.STATUS.SCHEDULED'),
  rescheduled: t('CONVERSATION_SIDEBAR.APPOINTMENTS.STATUS.RESCHEDULED'),
  confirmed: t('CONVERSATION_SIDEBAR.APPOINTMENTS.STATUS.CONFIRMED'),
}));

const SELECT_CLASS =
  '!mb-0 h-10 bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg pl-3 pr-9 text-sm text-n-slate-12 focus:outline-n-brand';
const DATE_CLASS =
  '!mb-0 h-10 bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg px-3 text-sm text-n-slate-12 focus:outline-n-brand';
</script>

<template>
  <ReportHeader
    :header-title="$t('APPOINTMENTS_REPORT.HEADER')"
    :header-description="$t('APPOINTMENTS_REPORT.DESCRIPTION')"
  />

  <div
    class="flex flex-col gap-3 mb-4 lg:flex-row lg:items-center lg:flex-wrap"
  >
    <select
      v-model="preset"
      :aria-label="$t('APPOINTMENTS_REPORT.PERIOD')"
      :class="SELECT_CLASS"
      class="lg:w-48"
      @change="preset !== 'custom' && applyPreset()"
    >
      <option value="today">
        {{ $t('APPOINTMENTS_REPORT.PRESETS.TODAY') }}
      </option>
      <option value="tomorrow">
        {{ $t('APPOINTMENTS_REPORT.PRESETS.TOMORROW') }}
      </option>
      <option value="next7">
        {{ $t('APPOINTMENTS_REPORT.PRESETS.NEXT_7') }}
      </option>
      <option value="next30">
        {{ $t('APPOINTMENTS_REPORT.PRESETS.NEXT_30') }}
      </option>
      <option value="custom">
        {{ $t('APPOINTMENTS_REPORT.PRESETS.CUSTOM') }}
      </option>
    </select>
    <div class="flex items-center gap-2 text-sm text-n-slate-11">
      <label class="flex items-center gap-2">
        {{ $t('APPOINTMENTS_REPORT.FROM') }}
        <input
          v-model="fromDate"
          type="date"
          :class="DATE_CLASS"
          @change="onDateChange"
        />
      </label>
      <label class="flex items-center gap-2">
        {{ $t('APPOINTMENTS_REPORT.TO') }}
        <input
          v-model="toDate"
          type="date"
          :min="fromDate"
          :class="DATE_CLASS"
          @change="onDateChange"
        />
      </label>
    </div>
    <select
      v-model="professional"
      :aria-label="$t('APPOINTMENTS_REPORT.COLUMNS.PROFESSIONAL')"
      :class="SELECT_CLASS"
      class="lg:w-56"
      @change="fetchData()"
    >
      <option value="">
        {{ $t('APPOINTMENTS_REPORT.ALL_PROFESSIONALS') }}
      </option>
      <option
        v-for="name in filterOptions.professionals"
        :key="name"
        :value="name"
      >
        {{ name }}
      </option>
    </select>
    <select
      v-model="erpSourceId"
      :aria-label="$t('APPOINTMENTS_REPORT.COLUMNS.SOURCE')"
      :class="SELECT_CLASS"
      class="lg:w-48"
      @change="fetchData()"
    >
      <option value="">{{ $t('APPOINTMENTS_REPORT.ALL_SOURCES') }}</option>
      <option
        v-for="source in filterOptions.erp_sources"
        :key="source.id"
        :value="source.id"
      >
        {{ source.name }}
      </option>
    </select>
  </div>

  <div
    v-if="error"
    class="px-4 py-3 mb-4 text-sm rounded-lg bg-n-ruby-3 text-n-ruby-12"
  >
    {{ $t('APPOINTMENTS_REPORT.ERROR_LOAD', { error }) }}
  </div>

  <div
    class="shadow bg-n-solid-2 outline outline-1 outline-n-container rounded-xl"
  >
    <h2 class="px-5 py-3 m-0 text-base font-medium text-n-slate-12">
      {{ $t('APPOINTMENTS_REPORT.TOTAL', { count: meta.total_count }) }}
    </h2>
    <div class="overflow-x-auto">
      <table class="w-full text-sm">
        <thead class="bg-n-slate-1 text-n-slate-12">
          <tr>
            <th
              class="px-5 py-3 text-sm font-medium text-left whitespace-nowrap"
            >
              {{ $t('APPOINTMENTS_REPORT.COLUMNS.DATETIME') }}
            </th>
            <th class="px-5 py-3 text-sm font-medium text-left">
              {{ $t('APPOINTMENTS_REPORT.COLUMNS.STATUS') }}
            </th>
            <th class="px-5 py-3 text-sm font-medium text-left">
              {{ $t('APPOINTMENTS_REPORT.COLUMNS.CONTACT') }}
            </th>
            <th class="px-5 py-3 text-sm font-medium text-left">
              {{ $t('APPOINTMENTS_REPORT.COLUMNS.PROFESSIONAL') }}
            </th>
            <th class="px-5 py-3 text-sm font-medium text-left">
              {{ $t('APPOINTMENTS_REPORT.COLUMNS.PROCEDURE') }}
            </th>
            <th class="px-5 py-3 text-sm font-medium text-left">
              {{ $t('APPOINTMENTS_REPORT.COLUMNS.SOURCE') }}
            </th>
            <th class="px-5 py-3 text-sm font-medium text-left">
              {{ $t('APPOINTMENTS_REPORT.COLUMNS.CONVERSATION') }}
            </th>
            <th
              class="px-5 py-3 text-sm font-medium text-left whitespace-nowrap"
            >
              {{ $t('APPOINTMENTS_REPORT.COLUMNS.INBOX') }}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-n-slate-2">
          <template v-if="!loading">
            <tr
              v-for="row in rows"
              :key="row.id"
              class="align-top text-n-slate-12 hover:bg-n-alpha-1"
            >
              <td
                class="px-5 py-3 font-semibold whitespace-nowrap text-n-teal-11"
              >
                {{ formatDate(row.scheduled_for) }}
              </td>
              <td class="px-5 py-3 whitespace-nowrap">
                <span
                  class="inline-flex px-2 py-0.5 rounded-full text-xs font-medium"
                  :class="STATUS_CLASS[row.status]"
                >
                  {{ statusLabels[row.status] }}
                </span>
              </td>
              <td class="px-5 py-3">
                <div class="font-medium">
                  {{ row.contact_name || $t('APPOINTMENTS_REPORT.DASH') }}
                </div>
                <div class="text-xs text-n-slate-11">
                  {{ row.contact_phone }}
                </div>
              </td>
              <td class="px-5 py-3">
                {{ row.professional_name || $t('APPOINTMENTS_REPORT.DASH') }}
              </td>
              <td class="px-5 py-3">
                {{ row.procedure_name || $t('APPOINTMENTS_REPORT.DASH') }}
              </td>
              <td class="px-5 py-3 text-n-slate-11">
                {{ row.source_name || $t('APPOINTMENTS_REPORT.DASH') }}
              </td>
              <td class="px-5 py-3 whitespace-nowrap">
                <a
                  :href="conversationUrl(row)"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="font-mono text-n-brand hover:underline"
                >
                  {{
                    $t('APPOINTMENTS_REPORT.HASH_ID', {
                      id: row.conversation_id,
                    })
                  }}
                </a>
              </td>
              <td class="px-5 py-3 whitespace-nowrap text-n-slate-11">
                {{ row.inbox_name }}
              </td>
            </tr>
          </template>
          <tr v-if="!rows.length && !loading">
            <td colspan="8" class="px-5 py-8 text-center text-n-slate-11">
              {{ $t('APPOINTMENTS_REPORT.EMPTY_STATE') }}
            </td>
          </tr>
          <tr v-if="loading">
            <td colspan="8" class="px-5 py-8 text-center text-n-slate-11">
              {{ $t('APPOINTMENTS_REPORT.LOADING') }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <div class="px-5 py-3 border-t border-n-slate-2">
      <PaginationFooter
        :current-page="currentPage"
        :total-items="meta.total_count"
        :items-per-page="meta.per_page"
        class="!px-0"
        @update:current-page="fetchData"
      />
    </div>
  </div>
</template>
