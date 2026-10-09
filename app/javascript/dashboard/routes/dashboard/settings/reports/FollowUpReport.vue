<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { getUnixStartOfDay, getUnixEndOfDay } from 'helpers/DateHelper';
import { DATE_RANGE_TYPES } from 'dashboard/components/ui/DatePicker/helpers/DatePickerHelper';
import { downloadCsvFile } from 'dashboard/helper/downloadHelper';
import WootDatePicker from 'dashboard/components/ui/DatePicker/DatePicker.vue';
import ReportHeader from './components/ReportHeader.vue';
import FollowUpReportsAPI from 'dashboard/api/followUpReports';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const store = useStore();
const route = useRoute();
const { t } = useI18n();

const inboxes = computed(() => store.getters['inboxes/getInboxes']);
const HOURS = Array.from({ length: 24 }, (_, hour) => hour);

const today = new Date();
const customDateRange = ref([today, today]);
const selectedDateRange = ref(DATE_RANGE_TYPES.CUSTOM_RANGE);
const inboxId = ref('');
const hourFrom = ref('');
const hourTo = ref('');
const contactQuery = ref('');

const rows = ref([]);
const steps = ref([]);
const totals = ref({
  total_conversations: 0,
  conversations_with_follow_up: 0,
  reengaged_conversations: 0,
});
const currentPage = ref(1);
const meta = ref({ current_page: 1, per_page: 50, total_count: 0 });
const loading = ref(false);
const exporting = ref(false);
const error = ref(null);
const hasFetched = ref(false);

const accountId = computed(() => route.params.accountId);
const conversationUrl = row =>
  `/app/accounts/${accountId.value}/conversations/${row.conversation_id}`;

const filters = computed(() => ({
  from: getUnixStartOfDay(customDateRange.value[0]),
  to: getUnixEndOfDay(customDateRange.value[1]),
  inboxId: inboxId.value,
  hourFrom: hourFrom.value,
  hourTo: hourTo.value,
  q: contactQuery.value.trim(),
}));

const fetchData = async (page = 1) => {
  currentPage.value = page;
  loading.value = true;
  error.value = null;
  try {
    const { data } = await FollowUpReportsAPI.fetch({ ...filters.value, page });
    rows.value = data.rows || [];
    steps.value = data.steps || [];
    totals.value = data.totals || totals.value;
    meta.value = data.meta || meta.value;
    hasFetched.value = true;
  } catch (e) {
    error.value =
      e.response?.data?.error || e.response?.statusText || e.message;
  } finally {
    loading.value = false;
  }
};

const exportCsv = async () => {
  exporting.value = true;
  try {
    const { data } = await FollowUpReportsAPI.exportCsv(filters.value);
    downloadCsvFile('follow-ups.csv', data);
  } catch (e) {
    error.value =
      e.response?.data?.error || e.response?.statusText || e.message;
  } finally {
    exporting.value = false;
  }
};

const onDateRangeChange = value => {
  const [startDate, endDate, rangeType] = value;
  customDateRange.value = [startDate, endDate];
  selectedDateRange.value = rangeType || DATE_RANGE_TYPES.CUSTOM_RANGE;
  fetchData();
};

onMounted(() => {
  store.dispatch('inboxes/get');
  fetchData();
});

const percent = (part, whole) => {
  if (!whole) return '0%';
  return `${((part / whole) * 100).toFixed(1).replace('.', ',')}%`;
};

const withFollowUpRate = computed(() =>
  percent(
    totals.value.conversations_with_follow_up,
    totals.value.total_conversations
  )
);
const reengagementRate = computed(() =>
  percent(
    totals.value.reengaged_conversations,
    totals.value.conversations_with_follow_up
  )
);

// FUP waiting times as the team configures them: 30min, 4h, 1d 2h, 3d.
const delayLabel = minutes => {
  const days = Math.floor(minutes / 1440);
  const hours = Math.floor((minutes % 1440) / 60);
  const rest = minutes % 60;
  if (days) return hours ? `${days}d ${hours}h` : `${days}d`;
  if (hours) return rest ? `${hours}h${rest}min` : `${hours}h`;
  return `${rest}min`;
};

const stepLabel = item =>
  t('FOLLOW_UP_REPORT.STEP_LABEL', {
    step: item.step,
    delay: delayLabel(item.delay_minutes),
  });

const stepRate = item => percent(item.reengaged, item.sent);
const stepBarWidth = item =>
  item.sent ? `${Math.min((item.reengaged / item.sent) * 100, 100)}%` : '0%';

const DELIVERY_CLASS = {
  pending: 'bg-n-alpha-2 text-n-slate-11',
  sent: 'bg-n-teal-3 text-n-teal-11',
  failed: 'bg-n-ruby-3 text-n-ruby-11',
};

const OUTCOME_CLASS = {
  waiting: 'bg-n-blue-3 text-n-blue-11',
  reengaged: 'bg-n-teal-3 text-n-teal-11',
  closed: 'bg-n-amber-3 text-n-amber-11',
  no_response: 'bg-n-alpha-2 text-n-slate-11',
};

const deliveryLabel = status =>
  t(`FOLLOW_UP_REPORT.DELIVERY.${status.toUpperCase()}`);
const outcomeLabel = outcome =>
  t(`FOLLOW_UP_REPORT.OUTCOME.${outcome.toUpperCase()}`);
</script>

<template>
  <ReportHeader
    :header-title="$t('FOLLOW_UP_REPORT.HEADER')"
    :header-description="$t('FOLLOW_UP_REPORT.DESCRIPTION')"
  >
    <Button
      :label="$t('FOLLOW_UP_REPORT.EXPORT')"
      icon="i-lucide-download"
      variant="outline"
      color="slate"
      size="sm"
      :is-loading="exporting"
      @click="exportCsv"
    />
  </ReportHeader>

  <div class="flex flex-col w-full gap-3 mb-4 lg:flex-row lg:flex-wrap">
    <WootDatePicker
      v-model:date-range="customDateRange"
      v-model:range-type="selectedDateRange"
      @date-range-changed="onDateRangeChange"
    />

    <select
      v-model="inboxId"
      class="!mb-0 h-10 bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg pl-3 pr-9 text-sm text-n-slate-12 focus:outline-n-brand lg:w-64"
      @change="fetchData()"
    >
      <option value="">
        {{ $t('FOLLOW_UP_REPORT.ALL_INBOXES') }}
      </option>
      <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox.id">
        {{ inbox.name }}
      </option>
    </select>

    <div class="flex items-center gap-2 text-sm text-n-slate-11">
      <label class="flex items-center gap-2">
        {{ $t('FOLLOW_UP_REPORT.HOUR_FROM') }}
        <select
          v-model="hourFrom"
          class="!mb-0 h-10 bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg pl-3 pr-8 text-sm text-n-slate-12 focus:outline-n-brand"
          @change="fetchData()"
        >
          <option value="">{{ $t('FOLLOW_UP_REPORT.ANY_HOUR') }}</option>
          <option v-for="hour in HOURS" :key="hour" :value="hour">
            {{ $t('FOLLOW_UP_REPORT.HOUR', { hour }) }}
          </option>
        </select>
      </label>
      <label class="flex items-center gap-2">
        {{ $t('FOLLOW_UP_REPORT.HOUR_TO') }}
        <select
          v-model="hourTo"
          class="!mb-0 h-10 bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg pl-3 pr-8 text-sm text-n-slate-12 focus:outline-n-brand"
          @change="fetchData()"
        >
          <option value="">{{ $t('FOLLOW_UP_REPORT.ANY_HOUR') }}</option>
          <option v-for="hour in HOURS" :key="hour" :value="hour">
            {{ $t('FOLLOW_UP_REPORT.HOUR', { hour }) }}
          </option>
        </select>
      </label>
    </div>

    <input
      v-model="contactQuery"
      type="search"
      :placeholder="$t('FOLLOW_UP_REPORT.CONTACT_PLACEHOLDER')"
      :aria-label="$t('FOLLOW_UP_REPORT.CONTACT_PLACEHOLDER')"
      class="!mb-0 h-10 bg-n-alpha-black2 outline outline-1 outline-n-weak rounded-lg px-3 text-sm text-n-slate-12 focus:outline-n-brand lg:w-72"
      @keyup.enter="fetchData()"
      @search="fetchData()"
    />
  </div>

  <div
    v-if="error"
    class="px-4 py-3 mb-4 rounded-lg bg-n-ruby-3 text-n-ruby-12 text-sm"
  >
    {{ $t('FOLLOW_UP_REPORT.ERROR_LOAD', { error }) }}
  </div>

  <div v-if="hasFetched" class="grid grid-cols-1 gap-3 mb-6 md:grid-cols-3">
    <div
      class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow px-4 py-3"
    >
      <div class="text-xs text-n-slate-11">
        {{ $t('FOLLOW_UP_REPORT.KPI.TOTAL_CONVERSATIONS') }}
      </div>
      <div class="text-2xl font-medium text-n-slate-12 mt-1">
        {{ totals.total_conversations }}
      </div>
      <div class="text-xs text-n-slate-11 mt-1">
        {{ $t('FOLLOW_UP_REPORT.KPI.TOTAL_CONVERSATIONS_HINT') }}
      </div>
    </div>
    <div
      class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow px-4 py-3"
    >
      <div class="text-xs text-n-slate-11">
        {{ $t('FOLLOW_UP_REPORT.KPI.WITH_FOLLOW_UP') }}
      </div>
      <div class="text-2xl font-medium text-n-slate-12 mt-1">
        {{ totals.conversations_with_follow_up }}
        <span class="text-sm font-semibold text-n-blue-11 ml-1">{{
          withFollowUpRate
        }}</span>
      </div>
      <div class="text-xs text-n-slate-11 mt-1">
        {{ $t('FOLLOW_UP_REPORT.KPI.WITH_FOLLOW_UP_HINT') }}
      </div>
    </div>
    <div
      class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow px-4 py-3"
    >
      <div class="text-xs text-n-slate-11">
        {{ $t('FOLLOW_UP_REPORT.KPI.REENGAGEMENT') }}
      </div>
      <div class="text-2xl font-medium text-n-teal-11 mt-1">
        {{ reengagementRate }}
      </div>
      <div class="text-xs text-n-slate-11 mt-1">
        {{
          $t('FOLLOW_UP_REPORT.KPI.REENGAGEMENT_HINT', {
            count: totals.reengaged_conversations,
          })
        }}
      </div>
    </div>
  </div>

  <div
    v-if="hasFetched"
    class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow mb-6"
  >
    <h2 class="px-5 py-3 text-base font-medium text-n-slate-12 m-0">
      {{ $t('FOLLOW_UP_REPORT.SENT_TITLE') }}
    </h2>
    <div class="overflow-x-auto">
      <table class="w-full text-sm">
        <thead class="bg-n-slate-1 text-n-slate-12">
          <tr>
            <th
              class="text-left px-5 py-3 font-medium text-sm whitespace-nowrap"
            >
              {{ $t('FOLLOW_UP_REPORT.COLUMNS.DATETIME') }}
            </th>
            <th
              class="text-left px-5 py-3 font-medium text-sm whitespace-nowrap"
            >
              {{ $t('FOLLOW_UP_REPORT.COLUMNS.STEP') }}
            </th>
            <th class="text-left px-5 py-3 font-medium text-sm">
              {{ $t('FOLLOW_UP_REPORT.COLUMNS.CONTACT') }}
            </th>
            <th class="text-left px-5 py-3 font-medium text-sm">
              {{ $t('FOLLOW_UP_REPORT.COLUMNS.CONVERSATION') }}
            </th>
            <th
              class="text-left px-5 py-3 font-medium text-sm whitespace-nowrap"
            >
              {{ $t('FOLLOW_UP_REPORT.COLUMNS.INBOX') }}
            </th>
            <th class="text-left px-5 py-3 font-medium text-sm">
              {{ $t('FOLLOW_UP_REPORT.COLUMNS.DELIVERY') }}
            </th>
            <th class="text-left px-5 py-3 font-medium text-sm">
              {{ $t('FOLLOW_UP_REPORT.COLUMNS.OUTCOME') }}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-n-slate-2">
          <tr
            v-for="row in rows"
            :key="row.id"
            class="text-n-slate-12 hover:bg-n-alpha-1 align-top"
          >
            <td class="px-5 py-3 whitespace-nowrap text-n-slate-11">
              {{ row.sent_at }}
            </td>
            <td class="px-5 py-3 whitespace-nowrap">
              <span class="inline-flex items-center gap-2">
                <span
                  class="inline-flex items-center justify-center size-5 rounded-full border-2 border-n-blue-9 text-n-blue-11 text-[10px] font-bold"
                >
                  {{ row.step }}
                </span>
                {{ stepLabel(row) }}
              </span>
            </td>
            <td class="px-5 py-3">
              <div class="font-medium">
                {{ row.contact_name || $t('FOLLOW_UP_REPORT.DASH') }}
              </div>
              <div class="text-xs text-n-slate-11">
                {{ row.contact_phone }}
              </div>
            </td>
            <td class="px-5 py-3 whitespace-nowrap">
              <a
                :href="conversationUrl(row)"
                target="_blank"
                rel="noopener noreferrer"
                class="text-n-brand hover:underline font-mono"
              >
                {{
                  $t('FOLLOW_UP_REPORT.HASH_ID', { id: row.conversation_id })
                }}
              </a>
            </td>
            <td class="px-5 py-3 whitespace-nowrap text-n-slate-11">
              {{ row.inbox_name }}
            </td>
            <td class="px-5 py-3 whitespace-nowrap">
              <span
                class="inline-flex px-2 py-0.5 rounded-full text-xs font-medium"
                :class="DELIVERY_CLASS[row.delivery_status]"
                :title="row.error_message || undefined"
              >
                {{ deliveryLabel(row.delivery_status) }}
              </span>
              <div
                v-if="row.error_message"
                class="text-xs text-n-slate-11 mt-1 max-w-56 whitespace-normal"
              >
                {{ row.error_message }}
              </div>
            </td>
            <td class="px-5 py-3 whitespace-nowrap">
              <span
                class="inline-flex px-2 py-0.5 rounded-full text-xs font-medium"
                :class="OUTCOME_CLASS[row.outcome]"
              >
                {{ outcomeLabel(row.outcome) }}
              </span>
            </td>
          </tr>
          <tr v-if="!rows.length && !loading">
            <td colspan="7" class="px-5 py-8 text-center text-n-slate-11">
              {{ $t('FOLLOW_UP_REPORT.EMPTY_STATE') }}
            </td>
          </tr>
          <tr v-if="loading">
            <td colspan="7" class="px-5 py-8 text-center text-n-slate-11">
              {{ $t('FOLLOW_UP_REPORT.LOADING') }}
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

  <div
    v-if="hasFetched && steps.length"
    class="bg-n-solid-2 outline outline-1 outline-n-container rounded-xl shadow"
  >
    <div class="px-5 py-3">
      <h2 class="text-base font-medium text-n-slate-12 m-0">
        {{ $t('FOLLOW_UP_REPORT.STEPS.TITLE') }}
      </h2>
      <p class="text-xs text-n-slate-11 m-0 mt-1">
        {{ $t('FOLLOW_UP_REPORT.STEPS.DESCRIPTION') }}
      </p>
    </div>
    <div class="overflow-x-auto">
      <table class="w-full text-sm">
        <thead class="bg-n-slate-1 text-n-slate-12">
          <tr>
            <th class="text-left px-5 py-3 font-medium text-sm">
              {{ $t('FOLLOW_UP_REPORT.STEPS.STEP') }}
            </th>
            <th class="text-left px-5 py-3 font-medium text-sm">
              {{ $t('FOLLOW_UP_REPORT.STEPS.SENT') }}
            </th>
            <th class="text-left px-5 py-3 font-medium text-sm">
              {{ $t('FOLLOW_UP_REPORT.STEPS.REENGAGED') }}
            </th>
            <th class="text-left px-5 py-3 font-medium text-sm w-2/5">
              {{ $t('FOLLOW_UP_REPORT.STEPS.RATE') }}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-n-slate-2">
          <tr v-for="item in steps" :key="item.step" class="text-n-slate-12">
            <td class="px-5 py-3 font-medium whitespace-nowrap">
              {{ stepLabel(item) }}
            </td>
            <td class="px-5 py-3">{{ item.sent }}</td>
            <td class="px-5 py-3">{{ item.reengaged }}</td>
            <td class="px-5 py-3">
              <div class="flex items-center gap-3">
                <div
                  class="flex-1 h-2 rounded-full bg-n-alpha-2 overflow-hidden"
                >
                  <div
                    class="h-full rounded-full bg-n-blue-9"
                    :style="{ width: stepBarWidth(item) }"
                  />
                </div>
                <span class="font-semibold min-w-14 text-right">
                  {{ stepRate(item) }}
                </span>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
