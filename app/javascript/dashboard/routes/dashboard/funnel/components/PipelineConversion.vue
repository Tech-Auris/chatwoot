<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import subDays from 'date-fns/subDays';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { formatTimeLocalized } from 'dashboard/helper/timeFormatter';
import WootDatePicker from 'dashboard/components/ui/DatePicker/DatePicker.vue';
import { DATE_RANGE_TYPES } from 'dashboard/components/ui/DatePicker/helpers/DatePickerHelper';
import { getUnixStartOfDay, getUnixEndOfDay } from 'helpers/DateHelper';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import FunnelChart from './FunnelChart.vue';
import LossReasonsDonut from './LossReasonsDonut.vue';
import ReportLoadError from './ReportLoadError.vue';

// Conversão of a clinic pipeline: win rate, loss rate, average time until the
// win, the funnel from stage to stage and the loss reasons. The campaign grid
// belongs to the Agendamento only.
const props = defineProps({
  pipelineId: { type: Number, required: true },
});

const store = useStore();
const { t } = useI18n();

const customDateRange = ref([subDays(new Date(), 29), new Date()]);
const selectedDateRange = ref(DATE_RANGE_TYPES.LAST_30_DAYS);
const from = ref(getUnixStartOfDay(customDateRange.value[0]));
const to = ref(getUnixEndOfDay(customDateRange.value[1]));
const labelName = ref('');
const loadError = ref('');

const uiFlags = useMapGetter('summaryReports/getUIFlags');
const report = useMapGetter('summaryReports/getFunnelConversionReport');
const labels = useMapGetter('labels/getLabels');
const isLoading = computed(
  () => uiFlags.value.isFetchingFunnelConversionReports ?? false
);

const stages = computed(() =>
  loadError.value ? [] : report.value?.stages || []
);
const kpis = computed(() => (loadError.value ? {} : report.value?.kpis || {}));
const lossReasons = computed(() =>
  loadError.value ? [] : report.value?.lossReasons || []
);
const labelOptions = computed(() =>
  [...labels.value].sort((a, b) => a.title.localeCompare(b.title))
);

const formatRate = value =>
  value === null || value === undefined ? '--' : `${Number(value).toFixed(1)}%`;

const kpiCards = computed(() => [
  {
    key: 'won',
    label: t('PIPELINES.CONVERSION.WON_RATE'),
    value: formatRate(kpis.value.wonRate),
    detail: t('PIPELINES.CONVERSION.OF_TOTAL', {
      count: kpis.value.wonCount ?? 0,
      total: kpis.value.total ?? 0,
    }),
  },
  {
    key: 'lost',
    label: t('PIPELINES.CONVERSION.LOST_RATE'),
    value: formatRate(kpis.value.lostRate),
    detail: t('PIPELINES.CONVERSION.OF_TOTAL', {
      count: kpis.value.lostCount ?? 0,
      total: kpis.value.total ?? 0,
    }),
  },
  {
    key: 'time',
    label: t('PIPELINES.CONVERSION.AVG_TIME_TO_WON'),
    value: kpis.value.avgTimeToWon
      ? formatTimeLocalized(kpis.value.avgTimeToWon, t)
      : '--',
    detail: '',
  },
]);

const fetchReport = async () => {
  loadError.value = '';
  try {
    await store.dispatch('summaryReports/fetchFunnelConversionReports', {
      since: from.value,
      until: to.value,
      label: labelName.value || undefined,
      pipelineId: props.pipelineId,
    });
  } catch (error) {
    loadError.value = error?.response?.data?.error || t('REPORT.LOAD_FAILED');
  }
};

const onDateRangeChange = value => {
  const [startDate, endDate, rangeType] = value;
  customDateRange.value = [startDate, endDate];
  selectedDateRange.value = rangeType || DATE_RANGE_TYPES.CUSTOM_RANGE;
  from.value = getUnixStartOfDay(startDate);
  to.value = getUnixEndOfDay(endDate);
  fetchReport();
};

const onLabelChange = event => {
  labelName.value = event.target.value;
  fetchReport();
};

onMounted(fetchReport);
</script>

<template>
  <div class="flex flex-col flex-1 gap-3 px-6 py-5 overflow-auto">
    <section class="flex flex-col gap-2 pb-2">
      <span class="text-heading-1 text-n-slate-12">
        {{ t('FUNNEL_CONVERSION_REPORTS.HEADER') }}
      </span>
      <p class="text-n-slate-11 mb-0 text-body-main">
        {{ t('PIPELINES.CONVERSION.DESCRIPTION') }}
      </p>
    </section>

    <div
      class="flex flex-col flex-wrap items-start gap-3 md:flex-row"
      :class="{ 'pointer-events-none opacity-50': isLoading }"
    >
      <WootDatePicker
        v-model:date-range="customDateRange"
        v-model:range-type="selectedDateRange"
        @date-range-changed="onDateRangeChange"
      />
      <select
        :value="labelName"
        class="h-10 text-sm rounded-md border border-n-weak bg-n-input-background px-2 text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-blue-9 w-[10.5rem]"
        @change="onLabelChange"
      >
        <option value="">
          {{ t('FUNNEL_CONVERSION_REPORTS.FILTERS.LABEL_ANY') }}
        </option>
        <option
          v-for="label in labelOptions"
          :key="label.id"
          :value="label.title"
        >
          {{ label.title }}
        </option>
      </select>
    </div>

    <div class="grid grid-cols-1 gap-3 mt-2 sm:grid-cols-3">
      <div
        v-for="card in kpiCards"
        :key="card.key"
        class="px-5 py-4 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
      >
        <div class="text-sm text-n-slate-11 whitespace-nowrap">
          {{ card.label }}
        </div>
        <div class="mt-2 text-3xl font-semibold text-n-slate-12">
          {{ card.value }}
        </div>
        <div v-if="card.detail" class="mt-1 text-xs text-n-slate-11">
          {{ card.detail }}
        </div>
      </div>
    </div>

    <div class="relative mt-2 grid grid-cols-1 gap-3 md:grid-cols-3">
      <div
        v-if="loadError"
        class="md:col-span-3 px-6 py-5 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
      >
        <ReportLoadError :message="loadError" @retry="fetchReport" />
      </div>
      <template v-else>
        <div
          class="md:col-span-2 px-6 py-5 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
        >
          <div
            v-if="!isLoading && !kpis.total"
            class="py-10 text-center text-n-slate-11"
          >
            {{ t('FUNNEL_CONVERSION_REPORTS.EMPTY_STATE') }}
          </div>
          <FunnelChart v-else :stages="stages" :split-by-ai="false" />
        </div>
        <div
          class="md:col-span-1 px-6 py-5 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
        >
          <div class="text-sm font-medium text-n-slate-12 mb-4">
            {{ t('FUNNEL_CONVERSION_REPORTS.LOSS_REASONS.HEADER') }}
          </div>
          <div
            v-if="!isLoading && !lossReasons.length"
            class="py-10 text-center text-n-slate-11 text-sm"
          >
            {{ t('FUNNEL_CONVERSION_REPORTS.LOSS_REASONS.EMPTY_STATE') }}
          </div>
          <LossReasonsDonut v-else :reasons="lossReasons" />
        </div>
      </template>
      <div
        v-if="isLoading"
        class="absolute inset-0 flex justify-center pt-[6rem] bg-n-solid-1/70 rounded-xl pointer-events-none"
      >
        <Spinner :size="32" class="text-n-brand" />
      </div>
    </div>
  </div>
</template>
