<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { useI18n, I18nT } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import HomeAPI from 'dashboard/api/home';
import { ORIGEM_NONE_TOKEN } from 'dashboard/helper/origemOptions';
import HomeTodayCards from './components/HomeTodayCards.vue';
import HomeFilters from './components/HomeFilters.vue';
import MetricSparkCard from './components/MetricSparkCard.vue';
import camelcaseKeys from 'camelcase-keys';
import FunnelChart from 'dashboard/routes/dashboard/funnel/components/FunnelChart.vue';
import FunnelDrilldownDialog from 'dashboard/routes/dashboard/funnel/components/FunnelDrilldownDialog.vue';
import PieCard from './components/PieCard.vue';
import StatCard from './components/StatCard.vue';
import HomeDrilldownDialog from './components/HomeDrilldownDialog.vue';
import HomeWaitingDialog from './components/HomeWaitingDialog.vue';
import HomeFollowUpDialog from './components/HomeFollowUpDialog.vue';
import { formatDuration, variation } from './homeFormatters';

const REFRESH_EVERY = 60 * 1000;

const { t } = useI18n();
const currentUser = useMapGetter('getCurrentUser');
const currentRole = useMapGetter('getCurrentRole');

const period = ref('7d');
const customFrom = ref('');
const customTo = ref('');
const origem = ref('');
const inboxIds = ref([]);

const data = ref(null);
const waitingDialog = ref(null);
const followUpDialog = ref(null);
const cardDialog = ref(null);
const drilldownDialog = ref(null);
// The period of the numbers on screen, for the funnel drill-down.
const loadedRange = ref(null);
const loadError = ref(false);

const startOfDay = date => {
  const day = new Date(date);
  day.setHours(0, 0, 0, 0);
  return day;
};
const daysAgo = days => {
  const day = startOfDay(new Date());
  day.setDate(day.getDate() - days);
  return day;
};
const unix = date => Math.floor(date.getTime() / 1000);

// "Mês" is the last 30 days, so it always draws 4 or 5 full weeks. Read at
// each fetch, so the minute refresh always ends at "now".
const currentRange = () => {
  const now = new Date();
  if (period.value === 'custom' && customFrom.value && customTo.value) {
    const until = startOfDay(`${customTo.value}T00:00:00`);
    until.setDate(until.getDate() + 1);
    return {
      since: unix(startOfDay(`${customFrom.value}T00:00:00`)),
      until: unix(until),
    };
  }
  const back = { today: 0, '7d': 6, month: 29 }[period.value] ?? 6;
  return { since: unix(daysAgo(back)), until: unix(now) };
};

const fetchHome = async () => {
  try {
    const range = currentRange();
    const { data: payload } = await HomeAPI.get({
      ...range,
      origem: origem.value,
      inboxIds: inboxIds.value,
    });
    data.value = payload;
    loadedRange.value = range;
    loadError.value = false;
  } catch {
    loadError.value = true;
  }
};

watch([period, customFrom, customTo, origem, inboxIds], fetchHome);

let refreshTimer;
onMounted(() => {
  fetchHome();
  refreshTimer = setInterval(() => {
    if (!document.hidden) fetchHome();
  }, REFRESH_EVERY);
});
onUnmounted(() => clearInterval(refreshTimer));

const firstName = computed(() => (currentUser.value?.name || '').split(' ')[0]);

const greeting = computed(() => {
  const hour = new Date().getHours();
  let key = 'EVENING';
  if (hour < 12) key = 'MORNING';
  else if (hour < 18) key = 'AFTERNOON';
  return t(`HOME_OVERVIEW.GREETING.${key}`, { name: firstName.value });
});

const today = computed(() => data.value?.today);
const metrics = computed(() => data.value?.metrics);

const dataFrom = computed(() =>
  (data.value?.available_inboxes || []).map(inbox => inbox.name).join(', ')
);

// Same order as the approved mockup.
const counterCards = computed(() => [
  { key: 'leads', title: t('HOME_OVERVIEW.METRICS.LEADS') },
  { key: 'appointments', title: t('HOME_OVERVIEW.METRICS.APPOINTMENTS') },
  {
    key: 'off_hours_leads',
    title: t('HOME_OVERVIEW.METRICS.OFF_HOURS_LEADS'),
    info: t('HOME_OVERVIEW.METRICS.OFF_HOURS_INFO'),
  },
  {
    key: 'off_hours_appointments',
    title: t('HOME_OVERVIEW.METRICS.OFF_HOURS_APPOINTMENTS'),
    info: t('HOME_OVERVIEW.METRICS.OFF_HOURS_APPOINTMENTS_INFO'),
  },
  {
    key: 'follow_up_leads',
    title: t('HOME_OVERVIEW.METRICS.FOLLOW_UP_LEADS'),
  },
  {
    key: 'after_follow_up',
    title: t('HOME_OVERVIEW.METRICS.AFTER_FOLLOW_UP'),
  },
  {
    key: 'no_shows',
    title: t('HOME_OVERVIEW.METRICS.NO_SHOWS'),
    lowerIsBetter: true,
  },
  { key: 'attendances', title: t('HOME_OVERVIEW.METRICS.ATTENDANCES') },
]);

const responseTime = computed(() => metrics.value.response_time);
const responseDelta = computed(() =>
  variation(responseTime.value.average, responseTime.value.previous)
);

const aiShareDetail = computed(() => {
  const { share } = metrics.value.ai_conversations;
  return share === null
    ? ''
    : t('HOME_OVERVIEW.METRICS.AI_CONVERSATIONS_SHARE', {
        share: Math.round(share),
      });
});

const handoff = computed(() => metrics.value.handoff);
// The handoff moves in percentage points: 31% → 27% is "▼ 4 p.p.".
const handoffDelta = computed(() => {
  const { rate, previous_rate: previousRate } = handoff.value;
  if (rate === null || previousRate === null) return null;
  return Math.round(rate - previousRate);
});

const formatRate = rate => (rate === null ? '—' : `${Math.round(rate)}%`);

// Same chart as Funil → Conversão. Its drill-down reads the reports API,
// which only administrators and managers can open.
const canDrill = computed(() =>
  ['administrator', 'manager'].includes(currentRole.value)
);

const funnelStages = computed(() =>
  camelcaseKeys(metrics.value.funnel, { deep: true }).map(stage =>
    canDrill.value ? stage : { ...stage, drillable: false }
  )
);

// "Agendamentos após follow-up" has its own dialog, with the rows that come
// with the page; every other card lists its conversations on demand.
const onCardDrill = card => {
  if (card.key === 'after_follow_up') {
    followUpDialog.value?.open();
    return;
  }
  cardDialog.value?.open({
    metric: card.key,
    title: card.title,
    count: metrics.value[card.key].total,
  });
};

const TODAY_TITLES = {
  new_leads_today: 'HOME_OVERVIEW.TODAY.NEW_LEADS',
  booked_today: 'HOME_OVERVIEW.TODAY.BOOKED',
  tomorrow: 'HOME_OVERVIEW.TODAY.TOMORROW',
};
const TODAY_COUNTS = {
  new_leads_today: () => today.value.new_leads,
  booked_today: () => today.value.booked,
  tomorrow: () => today.value.tomorrow.scheduled,
};

const onTodayDrill = metric =>
  cardDialog.value?.open({
    metric,
    title: t(TODAY_TITLES[metric]),
    count: TODAY_COUNTS[metric](),
  });

// Origem dos leads lists the period's leads; Motivos de perda, the lost ones.
const onPieDrill = (metric, titleKey, slices) =>
  cardDialog.value?.open({
    metric,
    title: t(titleKey),
    count: slices.reduce((sum, slice) => sum + slice.count, 0),
  });

const drillFilters = computed(() => ({
  ...loadedRange.value,
  inboxIds: data.value.inboxes.map(inbox => inbox.id),
  origem: origem.value || undefined,
}));

const onStageDrill = stage =>
  drilldownDialog.value?.open({
    stageKey: stage.key,
    name: stage.name,
    count: stage.count,
  });

const originSlices = computed(() =>
  metrics.value.origins.map(row => ({
    label:
      row.origem === ORIGEM_NONE_TOKEN
        ? t('HOME_OVERVIEW.FILTERS.ORIGEM_NONE')
        : row.origem,
    count: row.count,
  }))
);

const lossSlices = computed(() =>
  metrics.value.loss_reasons.map(row => ({ label: row.name, count: row.count }))
);
</script>

<template>
  <div class="flex flex-col flex-1 gap-5 px-6 py-5 overflow-auto">
    <p v-if="loadError && !data" class="text-sm text-n-ruby-11">
      {{ t('HOME_OVERVIEW.LOAD_ERROR') }}
    </p>
    <template v-if="today">
      <section class="flex flex-col gap-1">
        <h1 class="mb-0 text-2xl font-semibold leading-snug text-n-slate-12">
          {{ greeting }}
          <I18nT keypath="HOME_OVERVIEW.GREETING.TODAY" tag="span">
            <template #verb>
              {{ t('HOME_OVERVIEW.GREETING.LEADS_VERB', today.new_leads) }}
            </template>
            <template #leads>
              <span class="text-n-brand">
                {{ t('HOME_OVERVIEW.GREETING.LEADS', today.new_leads) }}
              </span>
            </template>
            <template #booked>
              <span class="text-n-brand">
                {{ t('HOME_OVERVIEW.GREETING.BOOKED', today.booked) }}
              </span>
            </template>
          </I18nT>
        </h1>
        <p
          class="mb-0 text-2xl font-semibold leading-snug"
          :class="
            today.waiting.count
              ? 'text-[#d97706] dark:text-n-amber-11'
              : 'text-n-slate-11'
          "
        >
          {{ t('HOME_OVERVIEW.GREETING.WAITING', today.waiting.count) }}
        </p>
        <p class="mb-0 text-sm text-n-slate-11">
          {{ t('HOME_OVERVIEW.GREETING.DATA_FROM', { inboxes: dataFrom }) }}
        </p>
      </section>

      <HomeTodayCards
        :today="today"
        @open-waiting="waitingDialog?.open()"
        @drill="onTodayDrill"
      />
      <HomeWaitingDialog ref="waitingDialog" :waiting="today.waiting" />
      <FunnelDrilldownDialog ref="drilldownDialog" :filters="drillFilters" />
      <HomeDrilldownDialog ref="cardDialog" :filters="drillFilters" />
      <HomeFollowUpDialog
        ref="followUpDialog"
        :after-follow-up="metrics.after_follow_up"
      />

      <HomeFilters
        v-model:period="period"
        v-model:custom-from="customFrom"
        v-model:custom-to="customTo"
        v-model:origem="origem"
        v-model:inbox-ids="inboxIds"
        :inboxes="data.available_inboxes"
      />

      <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <MetricSparkCard
          v-for="card in counterCards"
          :key="card.key"
          :title="card.title"
          :metric="metrics[card.key]"
          :lower-is-better="card.lowerIsBetter"
          :info="card.info"
          drillable
          :buckets="metrics.buckets"
          :granularity="metrics.granularity"
          @drill="onCardDrill(card)"
        />
      </div>

      <div class="grid grid-cols-1 gap-3 lg:grid-cols-3">
        <div
          class="flex flex-col gap-3 px-4 py-3 lg:col-span-2 lg:row-span-2 rounded-xl bg-n-solid-2 outline outline-1 outline-n-container"
        >
          <div class="text-sm font-medium text-n-slate-12">
            {{ t('HOME_OVERVIEW.METRICS.FUNNEL') }}
          </div>
          <p v-if="!funnelStages.length" class="text-sm text-n-slate-10">
            {{ t('HOME_OVERVIEW.METRICS.EMPTY') }}
          </p>
          <FunnelChart v-else :stages="funnelStages" @drill="onStageDrill" />
        </div>
        <PieCard
          :title="t('HOME_OVERVIEW.METRICS.ORIGINS')"
          :slices="originSlices"
          @drill="
            onPieDrill('leads', 'HOME_OVERVIEW.METRICS.ORIGINS', originSlices)
          "
        />
        <PieCard
          :title="t('HOME_OVERVIEW.METRICS.LOSS_REASONS')"
          :slices="lossSlices"
          @drill="
            onPieDrill(
              'losses',
              'HOME_OVERVIEW.METRICS.LOSS_REASONS',
              lossSlices
            )
          "
        />
      </div>

      <div class="grid grid-cols-1 gap-3 lg:grid-cols-3">
        <StatCard
          :title="t('HOME_OVERVIEW.METRICS.RESPONSE_TIME')"
          :value="formatDuration(responseTime.average)"
          :delta="responseDelta"
          :previous-label="formatDuration(responseTime.previous)"
          lower-is-better
          :detail="
            t('HOME_OVERVIEW.METRICS.RESPONSE_TIME_SPLIT', {
              ai: formatDuration(responseTime.ai_average),
              team: formatDuration(responseTime.team_average),
            })
          "
        />
        <MetricSparkCard
          :title="t('HOME_OVERVIEW.METRICS.AI_CONVERSATIONS')"
          :metric="metrics.ai_conversations"
          :detail="aiShareDetail"
          :buckets="metrics.buckets"
          :granularity="metrics.granularity"
        />
        <StatCard
          :title="t('HOME_OVERVIEW.METRICS.HANDOFF')"
          :value="formatRate(handoff.rate)"
          :delta="handoffDelta"
          :previous-label="formatRate(handoff.previous_rate)"
          :delta-unit="t('HOME_OVERVIEW.METRICS.PERCENTAGE_POINTS')"
          lower-is-better
          :detail="
            t('HOME_OVERVIEW.METRICS.HANDOFF_DETAIL', {
              handed: handoff.handed_off,
              total: handoff.ai_conversations,
            })
          "
        />
      </div>
    </template>
  </div>
</template>
