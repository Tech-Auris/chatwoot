<script setup>
import { computed, h, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatTimeLocalized } from 'dashboard/helper/timeFormatter';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import {
  useVueTable,
  createColumnHelper,
  getCoreRowModel,
} from '@tanstack/vue-table';

import ReportHeader from './components/ReportHeader.vue';
import OverviewReportFilters from './components/OverviewReportFilters.vue';
import Table from 'dashboard/components/table/Table.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// The report is keyed by contact.additional_attributes.origem, which is a
// fixed vocabulary of 8 options + a synthetic "Sem origem" bucket (surfacing
// contacts that never got attributed — the operator needs to see those, not
// have them silently disappear from the totals). The metrics layout mirrors
// the Etiquetas overview report so operators get the same reading pattern.

const store = useStore();
const { t } = useI18n();

const from = ref(0);
const to = ref(0);
const businessHours = ref(false);

const uiFlags = useMapGetter('summaryReports/getUIFlags');
const isLoading = computed(
  () => uiFlags.value.isFetchingOrigemSummaryReports ?? false
);
const reportRows = useMapGetter('summaryReports/getOrigemSummaryReports');

const renderAvgTime = value => (value ? formatTimeLocalized(value, t) : '--');
const renderCount = value => (value ? value.toLocaleString() : '--');

const defaultSpanRender = cellProps =>
  h(
    'span',
    { class: cellProps.getValue() ? '' : 'text-n-slate-12' },
    cellProps.getValue()
  );

const columnHelper = createColumnHelper();
const columns = computed(() => [
  columnHelper.accessor('name', {
    header: t('ORIGEM_REPORTS.COLUMNS.NAME'),
    width: 300,
  }),
  columnHelper.accessor('conversationsCount', {
    header: t('ORIGEM_REPORTS.COLUMNS.CONVERSATIONS'),
    width: 200,
    cell: defaultSpanRender,
  }),
  columnHelper.accessor('avgFirstResponseTime', {
    header: t('ORIGEM_REPORTS.COLUMNS.AVG_FIRST_RESPONSE_TIME'),
    width: 200,
    cell: defaultSpanRender,
  }),
  columnHelper.accessor('avgResolutionTime', {
    header: t('ORIGEM_REPORTS.COLUMNS.AVG_RESOLUTION_TIME'),
    width: 200,
    cell: defaultSpanRender,
  }),
  columnHelper.accessor('avgReplyTime', {
    header: t('ORIGEM_REPORTS.COLUMNS.AVG_REPLY_TIME'),
    width: 200,
    cell: defaultSpanRender,
  }),
  columnHelper.accessor('resolutionsCount', {
    header: t('ORIGEM_REPORTS.COLUMNS.RESOLUTION_COUNT'),
    width: 200,
    cell: defaultSpanRender,
  }),
]);

const tableData = computed(() =>
  (reportRows.value || []).map(row => ({
    id: row.id,
    name: row.name,
    conversationsCount: renderCount(row.conversationsCount),
    avgFirstResponseTime: renderAvgTime(row.avgFirstResponseTime),
    avgResolutionTime: renderAvgTime(row.avgResolutionTime),
    avgReplyTime: renderAvgTime(row.avgReplyTime),
    resolutionsCount: renderCount(row.resolvedConversationsCount),
  }))
);

const fetchReports = async () => {
  try {
    await store.dispatch('summaryReports/fetchOrigemSummaryReports', {
      since: from.value,
      until: to.value,
      businessHours: businessHours.value,
    });
  } catch {
    useAlert(t('REPORT.SUMMARY_FETCHING_FAILED'));
  }
};

const onFilterChange = updatedFilter => {
  from.value = updatedFilter.from;
  to.value = updatedFilter.to;
  businessHours.value = updatedFilter.businessHours;
  fetchReports();
};

onMounted(fetchReports);

const table = useVueTable({
  get data() {
    return tableData.value;
  },
  get columns() {
    return columns.value;
  },
  enableSorting: false,
  getCoreRowModel: getCoreRowModel(),
});
</script>

<template>
  <ReportHeader
    :header-title="$t('ORIGEM_REPORTS.HEADER')"
    :header-description="$t('ORIGEM_REPORTS.DESCRIPTION')"
  />

  <OverviewReportFilters
    :disabled="isLoading"
    @filter-change="onFilterChange"
  />

  <div
    class="relative flex-1 overflow-auto px-2 py-2 mt-5 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
  >
    <Table :table="table" />
    <Transition
      enter-active-class="transition-opacity duration-300 ease-out"
      leave-active-class="transition-opacity duration-200 ease-in"
      enter-from-class="opacity-0"
      enter-to-class="opacity-100"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0"
    >
      <div
        v-if="isLoading"
        class="absolute inset-0 flex justify-center pt-[12.5rem] bg-n-solid-1/70 rounded-xl pointer-events-none"
      >
        <Spinner :size="32" class="text-n-brand" />
      </div>
    </Transition>
  </div>
</template>
