<script setup>
// The Fase 3 · F3 Analytics report. Aggregates per Meta ad the number of
// conversations initiated, funnel progression (qualified / scheduled /
// attendance), spend from Meta Marketing API, and derived CPL / CPA /
// ROAS. Google Ads campaigns show as spend-only rows because we don't
// tie conversations to specific Google campaigns.
//
// Date range defaults to "last 30 days" — matches operators' mental model
// of a monthly campaign review. Preset picker in the header, no custom
// range for MVP; F3.1 can add that.
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import SummaryReportsAPI from 'dashboard/api/summaryReports';

const PRESETS = [
  { key: 'LAST_7_DAYS', days: 7 },
  { key: 'LAST_30_DAYS', days: 30 },
  { key: 'LAST_90_DAYS', days: 90 },
];

const { t } = useI18n();
const selectedPreset = ref('LAST_30_DAYS');
const rows = ref([]);
const isLoading = ref(false);
const errorMessage = ref('');

const activePreset = computed(() =>
  PRESETS.find(preset => preset.key === selectedPreset.value)
);

const range = computed(() => {
  const now = new Date();
  const untilSeconds = Math.floor(now.getTime() / 1000);
  const sinceDate = new Date(now.getTime());
  sinceDate.setDate(sinceDate.getDate() - activePreset.value.days);
  const sinceSeconds = Math.floor(sinceDate.getTime() / 1000);
  return { since: sinceSeconds, until: untilSeconds };
});

const totals = computed(() =>
  rows.value.reduce(
    (acc, row) => ({
      conversations: acc.conversations + (row.conversations_count || 0),
      qualified: acc.qualified + (row.qualified_count || 0),
      scheduled: acc.scheduled + (row.scheduled_count || 0),
      attendance: acc.attendance + (row.attendance_count || 0),
      revenue_cents: acc.revenue_cents + (row.revenue_cents || 0),
      spend_cents: acc.spend_cents + (row.spend_cents || 0),
    }),
    {
      conversations: 0,
      qualified: 0,
      scheduled: 0,
      attendance: 0,
      revenue_cents: 0,
      spend_cents: 0,
    }
  )
);

const fetchData = async () => {
  isLoading.value = true;
  errorMessage.value = '';
  try {
    const { data } = await SummaryReportsAPI.getCampaignAnalytics(range.value);
    rows.value = data || [];
  } catch (err) {
    errorMessage.value =
      err?.response?.data?.message ||
      t('MARKETING_ANALYTICS_REPORT.LOAD_ERROR');
    rows.value = [];
  } finally {
    isLoading.value = false;
  }
};

const formatMoney = cents => {
  if (cents == null) return '—';
  const value = cents / 100;
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(value);
};

const formatRoas = roas => (roas == null ? '—' : `${roas.toFixed(2)}×`);

onMounted(fetchData);
watch(selectedPreset, fetchData);
</script>

<template>
  <div class="flex flex-col gap-4 p-6 w-full">
    <header class="flex items-start justify-between gap-4">
      <div>
        <h1 class="text-lg font-medium text-n-slate-12">
          {{ t('MARKETING_ANALYTICS_REPORT.TITLE') }}
        </h1>
        <p class="text-sm text-n-slate-11 mt-1">
          {{ t('MARKETING_ANALYTICS_REPORT.SUBTITLE') }}
        </p>
      </div>
      <select
        v-model="selectedPreset"
        class="rounded border border-n-strong bg-n-solid-2 px-2 py-1.5 text-sm text-n-slate-12"
      >
        <option v-for="preset in PRESETS" :key="preset.key" :value="preset.key">
          {{ t(`MARKETING_ANALYTICS_REPORT.PRESETS.${preset.key}`) }}
        </option>
      </select>
    </header>

    <div
      v-if="errorMessage"
      class="rounded border border-n-ruby-9/40 bg-n-ruby-3 text-n-ruby-11 p-3 text-sm"
    >
      {{ errorMessage }}
    </div>

    <div v-else-if="isLoading" class="text-sm text-n-slate-11 text-center py-8">
      {{ t('MARKETING_ANALYTICS_REPORT.LOADING') }}
    </div>

    <div
      v-else-if="!rows.length"
      class="text-sm text-n-slate-11 text-center py-8"
    >
      {{ t('MARKETING_ANALYTICS_REPORT.EMPTY') }}
    </div>

    <div v-else class="overflow-x-auto rounded-lg border border-n-strong">
      <table class="min-w-full text-sm">
        <thead class="bg-n-alpha-2">
          <tr class="text-n-slate-11 text-left">
            <th class="px-3 py-2 font-medium">
              {{ t('MARKETING_ANALYTICS_REPORT.COLUMNS.CAMPAIGN') }}
            </th>
            <th class="px-3 py-2 font-medium text-right">
              {{ t('MARKETING_ANALYTICS_REPORT.COLUMNS.CONVERSATIONS') }}
            </th>
            <th class="px-3 py-2 font-medium text-right">
              {{ t('MARKETING_ANALYTICS_REPORT.COLUMNS.QUALIFIED') }}
            </th>
            <th class="px-3 py-2 font-medium text-right">
              {{ t('MARKETING_ANALYTICS_REPORT.COLUMNS.SCHEDULED') }}
            </th>
            <th class="px-3 py-2 font-medium text-right">
              {{ t('MARKETING_ANALYTICS_REPORT.COLUMNS.ATTENDANCE') }}
            </th>
            <th class="px-3 py-2 font-medium text-right">
              {{ t('MARKETING_ANALYTICS_REPORT.COLUMNS.REVENUE') }}
            </th>
            <th class="px-3 py-2 font-medium text-right">
              {{ t('MARKETING_ANALYTICS_REPORT.COLUMNS.SPEND') }}
            </th>
            <th class="px-3 py-2 font-medium text-right">
              {{ t('MARKETING_ANALYTICS_REPORT.COLUMNS.CPL') }}
            </th>
            <th class="px-3 py-2 font-medium text-right">
              {{ t('MARKETING_ANALYTICS_REPORT.COLUMNS.CPA') }}
            </th>
            <th class="px-3 py-2 font-medium text-right">
              {{ t('MARKETING_ANALYTICS_REPORT.COLUMNS.ROAS') }}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-n-strong text-n-slate-12">
          <tr v-for="row in rows" :key="`${row.source_type}-${row.source_id}`">
            <td class="px-3 py-2">
              <div class="flex flex-col gap-0.5">
                <span class="text-n-slate-12">
                  {{ row.name || row.source_id }}
                </span>
                <span
                  class="text-[11px] uppercase text-n-slate-11 tracking-wide"
                >
                  {{
                    row.source_type === 'meta_ad'
                      ? t('MARKETING_ANALYTICS_REPORT.SOURCE.META')
                      : t('MARKETING_ANALYTICS_REPORT.SOURCE.GOOGLE')
                  }}
                </span>
              </div>
            </td>
            <td class="px-3 py-2 text-right">
              {{ row.conversations_count || 0 }}
            </td>
            <td class="px-3 py-2 text-right">{{ row.qualified_count || 0 }}</td>
            <td class="px-3 py-2 text-right">{{ row.scheduled_count || 0 }}</td>
            <td class="px-3 py-2 text-right">
              {{ row.attendance_count || 0 }}
            </td>
            <td class="px-3 py-2 text-right">
              {{ formatMoney(row.revenue_cents) }}
            </td>
            <td class="px-3 py-2 text-right">
              {{ formatMoney(row.spend_cents) }}
            </td>
            <td class="px-3 py-2 text-right">
              {{ formatMoney(row.cpl_cents) }}
            </td>
            <td class="px-3 py-2 text-right">
              {{ formatMoney(row.cpa_cents) }}
            </td>
            <td class="px-3 py-2 text-right">{{ formatRoas(row.roas) }}</td>
          </tr>
        </tbody>
        <tfoot class="bg-n-alpha-1 font-medium">
          <tr>
            <td class="px-3 py-2 text-n-slate-11 uppercase text-xs">
              {{ t('MARKETING_ANALYTICS_REPORT.TOTAL') }}
            </td>
            <td class="px-3 py-2 text-right">{{ totals.conversations }}</td>
            <td class="px-3 py-2 text-right">{{ totals.qualified }}</td>
            <td class="px-3 py-2 text-right">{{ totals.scheduled }}</td>
            <td class="px-3 py-2 text-right">{{ totals.attendance }}</td>
            <td class="px-3 py-2 text-right">
              {{ formatMoney(totals.revenue_cents) }}
            </td>
            <td class="px-3 py-2 text-right">
              {{ formatMoney(totals.spend_cents) }}
            </td>
            <td class="px-3 py-2" colspan="3" />
          </tr>
        </tfoot>
      </table>
    </div>
  </div>
</template>
