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
import Icon from 'dashboard/components-next/icon/Icon.vue';
import FunnelDrilldownDialog from 'dashboard/routes/dashboard/funnel/components/FunnelDrilldownDialog.vue';

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

const SUM_FIELDS = [
  'conversations_count',
  'qualified_count',
  'scheduled_count',
  'confirmed_count',
  'attendance_count',
  'revenue_cents',
  'spend_cents',
];

const totals = computed(() =>
  Object.fromEntries(
    SUM_FIELDS.map(field => [
      field,
      rows.value.reduce((sum, row) => sum + (row[field] || 0), 0),
    ])
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

// Columns whose number opens the conversations behind it (Meta ads only —
// Google rows carry spend, no conversations).
const DRILL_COLUMNS = [
  { metric: 'conversations', field: 'conversations_count', label: 'LEADS' },
  { metric: 'qualified', field: 'qualified_count', label: 'QUALIFYING' },
  { metric: 'scheduled', field: 'scheduled_count', label: 'SCHEDULING' },
  { metric: 'confirmed', field: 'confirmed_count', label: 'CONFIRMATION' },
  { metric: 'attendance', field: 'attendance_count', label: 'ATTENDANCE' },
];

// Share of the ad's leads that reached the stage, like the funnel's ad grid.
const stageRate = (count, leads) =>
  leads > 0 ? `${((count / leads) * 100).toFixed(1)}%` : null;

const drilldownRef = ref(null);
const drilldownFilters = computed(() => ({
  since: range.value.since,
  until: range.value.until,
}));

const canDrill = (row, column) =>
  row.source_type === 'meta_ad' && (row[column.field] || 0) > 0;

const openDrilldown = (row, column) =>
  drilldownRef.value?.open({
    kind: 'ad',
    sourceId: row.source_id,
    metric: column.metric,
    metricLabel: t(`MARKETING_ANALYTICS_REPORT.COLUMNS.${column.label}`),
    name: row.name || row.source_id,
    count: row[column.field],
  });

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
            <th
              v-for="column in DRILL_COLUMNS"
              :key="column.metric"
              class="px-3 py-2 font-medium text-right whitespace-nowrap"
            >
              {{ t(`MARKETING_ANALYTICS_REPORT.COLUMNS.${column.label}`) }}
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
            <td
              v-for="column in DRILL_COLUMNS"
              :key="column.metric"
              class="px-3 py-2 text-right"
            >
              <button
                v-if="canDrill(row, column)"
                type="button"
                class="group inline-flex items-center justify-end gap-1 text-n-slate-12 hover:text-n-brand"
                @click="openDrilldown(row, column)"
              >
                {{ row[column.field] }}
                <Icon
                  icon="i-lucide-external-link"
                  class="size-3 text-n-slate-10 group-hover:text-n-brand"
                />
              </button>
              <span v-else>{{ row[column.field] || 0 }}</span>
              <div
                v-if="
                  column.metric !== 'conversations' &&
                  stageRate(row[column.field] || 0, row.conversations_count)
                "
                class="text-xs text-n-slate-11"
              >
                {{ stageRate(row[column.field] || 0, row.conversations_count) }}
              </div>
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
            <td
              v-for="column in DRILL_COLUMNS"
              :key="column.metric"
              class="px-3 py-2 text-right"
            >
              {{ totals[column.field] }}
              <div
                v-if="
                  column.metric !== 'conversations' &&
                  stageRate(totals[column.field], totals.conversations_count)
                "
                class="text-xs font-normal text-n-slate-11"
              >
                {{
                  stageRate(totals[column.field], totals.conversations_count)
                }}
              </div>
            </td>
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

    <FunnelDrilldownDialog ref="drilldownRef" :filters="drilldownFilters" />
  </div>
</template>
